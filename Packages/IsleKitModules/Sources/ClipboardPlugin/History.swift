import CSQLCipher
import CryptoKit
import Foundation
import ImageIO

struct StorageError: LocalizedError {
  var errorDescription: String?
  init(_ message: String) { errorDescription = message }
}

private enum Value {
  case text(String)
  case data(Data)
  case integer(Int64)
}

private final class CipherDatabase {
  private let handle: OpaquePointer
  init(url: URL, key: Data) throws {
    guard key.count == 32 else { throw StorageError("数据库密钥长度无效") }
    var db: OpaquePointer?
    let mode = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
    guard sqlite3_open_v2(url.path, &db, mode, nil) == SQLITE_OK, let db else {
      sqlite3_close(db)
      throw StorageError("无法打开历史数据库")
    }
    handle = db
    let hex = key.map { String(format: "%02x", $0) }.joined()
    try exec("PRAGMA key = \"x'\(hex)'\"")
    guard try rows("PRAGMA cipher_version", [], { Self.string($0, 0) }).first?.isEmpty == false
    else { throw StorageError("SQLCipher 未启用") }
    try exec("SELECT count(*) FROM sqlite_master")
    sqlite3_busy_timeout(db, 3000)
  }
  deinit { sqlite3_close(handle) }
  func exec(_ sql: String) throws {
    guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
  }
  func rows<T>(_ sql: String, _ values: [Value], _ row: (OpaquePointer) throws -> T) throws -> [T] {
    var query: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &query, nil) == SQLITE_OK, let query else {
      throw error()
    }
    defer { sqlite3_finalize(query) }
    let copy = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (i, value) in values.enumerated() {
      let index = Int32(i + 1)
      let status: Int32
      switch value {
      case .text(let text):
        status = sqlite3_bind_text(query, index, text, Int32(text.utf8.count), copy)
      case .data(let data):
        status = data.withUnsafeBytes {
          sqlite3_bind_blob(query, index, $0.baseAddress, Int32($0.count), copy)
        }
      case .integer(let number): status = sqlite3_bind_int64(query, index, number)
      }
      guard status == SQLITE_OK else { throw error() }
    }
    var results: [T] = []
    while true {
      switch sqlite3_step(query) {
      case SQLITE_ROW: results.append(try row(query))
      case SQLITE_DONE: return results
      default: throw error()
      }
    }
  }
  func update(_ sql: String, _ values: [Value]) throws { _ = try rows(sql, values) { _ in () } }
  func transaction<T>(_ work: () throws -> T) throws -> T {
    try exec("BEGIN IMMEDIATE")
    do {
      let value = try work()
      try exec("COMMIT")
      return value
    } catch {
      try? exec("ROLLBACK")
      throw error
    }
  }
  static func string(_ row: OpaquePointer, _ column: Int32) -> String {
    guard let pointer = sqlite3_column_text(row, column) else { return "" }
    return String(
      decoding: UnsafeBufferPointer(start: pointer, count: Int(sqlite3_column_bytes(row, column))),
      as: UTF8.self)
  }
  static func data(_ row: OpaquePointer, _ column: Int32) -> Data {
    guard let bytes = sqlite3_column_blob(row, column) else { return Data() }
    return Data(bytes: bytes, count: Int(sqlite3_column_bytes(row, column)))
  }
  private func error() -> StorageError { StorageError(String(cString: sqlite3_errmsg(handle))) }
}

public struct HistoryItem: Identifiable, Sendable {
  public let id: String, kind: String, preview: String
  public let pinned: Bool
}

public actor History {
  private var connection: CipherDatabase?
  let url: URL
  public init(url: URL) {
    self.url = url
  }
  private func db() throws -> CipherDatabase {
    if let connection { return connection }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let key = try loadClipboardKey(existing: FileManager.default.fileExists(atPath: url.path))
    let db = try CipherDatabase(url: url, key: key)
    try db.exec(
      """
      PRAGMA journal_mode=WAL;
      CREATE TABLE IF NOT EXISTS clips(id TEXT PRIMARY KEY, kind TEXT NOT NULL, preview TEXT NOT NULL, payload BLOB NOT NULL, time INTEGER NOT NULL, pinned INTEGER NOT NULL DEFAULT 0);
      CREATE INDEX IF NOT EXISTS clip_order ON clips(pinned DESC,time DESC);
      """)
    connection = db
    return db
  }

  private static func save(_ db: CipherDatabase, kind: String, payload: Data, time: Int64, pinned: Bool)
    throws
  {
    guard ["text", "image"].contains(kind), !payload.isEmpty else {
      throw StorageError("记录类型或内容无效")
    }
    var hash = SHA256()
    hash.update(data: Data(kind.utf8))
    hash.update(data: payload)
    let id = hash.finalize().map { String(format: "%02x", $0) }.joined()
    let preview =
      kind == "text"
      ? String(String(decoding: payload, as: UTF8.self).prefix(160))
      : "图片 · \(ByteCountFormatter.string(fromByteCount: Int64(payload.count), countStyle: .file))"
    try db.update(
      """
      INSERT INTO clips(id,kind,preview,payload,time,pinned) VALUES(?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET time=MAX(time,excluded.time),pinned=MAX(pinned,excluded.pinned)
      """,
      [
        .text(id), .text(kind), .text(preview), .data(payload), .integer(time),
        .integer(pinned ? 1 : 0),
      ])
  }
  public func add(kind: String, data: Data, days: Int = 30, limit: Int = 1000) throws {
    let db = try db()
    let time = Int64(Date().timeIntervalSince1970 * 1000)
    guard data.count <= 32 * 1024 * 1024 else { throw StorageError("单条记录超过 32 MB") }
    try db.transaction {
      try Self.save(db, kind: kind, payload: data, time: time, pinned: false)
      try db.update(
        "DELETE FROM clips WHERE pinned=0 AND time < ?",
        [.integer(time - Int64(max(1, days)) * 86_400_000)])
      try db.update(
        "DELETE FROM clips WHERE id IN (SELECT id FROM clips WHERE pinned=0 ORDER BY time DESC LIMIT -1 OFFSET ?)",
        [.integer(Int64(max(1, limit)))])
      try db.exec(
        """
        DELETE FROM clips WHERE id IN (SELECT id FROM
          (SELECT id,pinned,SUM(length(payload)) OVER (ORDER BY pinned DESC,time DESC,id) AS total FROM clips)
          WHERE pinned=0 AND total>536870912)
        """)
    }
  }
  public func items(query: String = "", limit: Int = 100) throws -> [HistoryItem] {
    try db().rows(
      "SELECT id,kind,preview,pinned FROM clips WHERE ?='' OR (kind='text' AND instr(lower(CAST(payload AS TEXT)),lower(?))>0) ORDER BY pinned DESC,time DESC,id LIMIT ?",
      [.text(query), .text(query), .integer(Int64(limit))]
    ) {
      HistoryItem(
        id: CipherDatabase.string($0, 0), kind: CipherDatabase.string($0, 1),
        preview: CipherDatabase.string($0, 2), pinned: sqlite3_column_int($0, 3) != 0)
    }
  }
  public func payload(_ id: String) throws -> Data? {
    try db().rows("SELECT payload FROM clips WHERE id=?", [.text(id)]) {
      CipherDatabase.data($0, 0)
    }.first
  }
  public func pin(_ id: String) throws {
    try db().update("UPDATE clips SET pinned=1-pinned WHERE id=?", [.text(id)])
  }
  public func remove(_ id: String) throws {
    try db().update("DELETE FROM clips WHERE id=?", [.text(id)])
  }
  func removeAll() throws {
    try db().exec("DELETE FROM clips")
  }
  func imagePreview(_ id: String, maxPixels: Int) throws -> CGImage? {
    try Task.checkCancellation()
    guard let data = try payload(id),
      let source = CGImageSourceCreateWithData(data as CFData, nil)
    else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }
}
