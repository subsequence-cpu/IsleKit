import CryptoKit
import Foundation

public struct ToolFailure: LocalizedError {
  public let errorDescription: String?
  init(_ message: String) { errorDescription = message }
}

public enum Utility: String, CaseIterable, Sendable {
  case json, base64, url, unicode, hex, timestamp, hash, jwt, uuid, text, diff, regex

  public var title: String {
    switch self {
    case .json: "JSON 格式化"
    case .base64: "Base64 编解码"
    case .url: "URL 编解码"
    case .unicode: "Unicode 转换"
    case .hex: "Hex / String"
    case .timestamp: "时间戳转换"
    case .hash: "哈希与 HMAC"
    case .jwt: "JWT 解码"
    case .uuid: "UUID / 随机字符串"
    case .text: "文本处理"
    case .diff: "文本对比"
    case .regex: "正则表达式"
    }
  }

  public var operations: [String] {
    switch self {
    case .json: ["格式化", "压缩", "校验", "转义", "去转义"]
    case .base64, .url, .hex, .unicode: ["编码", "解码"]
    case .timestamp: ["时间戳 → 日期", "日期 → 时间戳"]
    case .hash: ["SHA256", "SHA512", "SHA384", "SHA1", "MD5", "HMAC-SHA256", "HMAC-SHA512"]
    case .jwt: ["解码（未验签）"]
    case .uuid: ["UUID", "随机字符串"]
    case .text: ["按行去重", "按行排序", "大写", "小写", "清理空白", "统计"]
    case .diff: ["逐行对比"]
    case .regex: ["匹配和捕获", "替换"]
    }
  }

  public var icon: String {
    switch self {
    case .json: "braces"
    case .timestamp: "clock"
    case .diff: "code-review"
    default: "terminal"
    }
  }

  public var sample: String {
    switch self {
    case .json: #"{"tool":"IsleKit","local":true}"#
    case .timestamp: "1792112400"
    case .jwt: "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJpc2xla2l0In0.signature"
    case .diff: "岛匣\nmacOS"
    case .regex: "hello@islekit.local"
    case .uuid: ""
    default: "Hello, 岛匣!"
    }
  }

  public func run(
    _ input: String, operation: String, extra: String = "", replacement: String = "",
    indent: Int = 2
  ) throws -> String {
    guard operations.contains(operation) else { throw ToolFailure("未知操作") }
    let decode = operation == "解码"
    func utf8(_ data: Data?) throws -> String {
      guard let data, let text = String(data: data, encoding: .utf8) else {
        throw ToolFailure("输入无效或结果不是 UTF-8 文本")
      }
      return text
    }
    func jsonData(_ value: Any, pretty: Bool) throws -> String {
      let options: JSONSerialization.WritingOptions =
        pretty
        ? [.prettyPrinted, .sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]
        : [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
      let data = try JSONSerialization.data(withJSONObject: value, options: options)
      let result = try utf8(data)
      if pretty && indent == 4 {
        return result.components(separatedBy: "\n").map {
          String(repeating: " ", count: $0.prefix(while: { $0 == " " }).count) + $0
        }.joined(separator: "\n")
      }
      return result
    }
    let bytes = Data(input.utf8)
    switch self {
    case .json:
      if operation == "转义" { return try jsonData(input, pretty: false) }
      let value = try JSONSerialization.jsonObject(with: bytes, options: .fragmentsAllowed)
      if operation == "校验" { return "JSON 格式正确" }
      if operation == "去转义" {
        guard let string = value as? String else { throw ToolFailure("请输入 JSON 字符串") }
        return string
      }
      return try jsonData(value, pretty: operation == "格式化")
    case .base64:
      return decode
        ? try utf8(Data(base64Encoded: input.filter { !$0.isWhitespace }))
        : bytes.base64EncodedString()
    case .url:
      if decode {
        guard let decoded = input.removingPercentEncoding else { throw ToolFailure("无效的百分号编码") }
        return decoded
      }
      return bytes.map { byte in
        let safe =
          (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
          || [45, 46, 95, 126].contains(byte)
        return safe ? String(UnicodeScalar(byte)) : String(format: "%%%02X", byte)
      }.joined()
    case .unicode:
      if !decode { return input.utf16.map { String(format: "\\u%04X", $0) }.joined() }
      let pieces = input.components(separatedBy: "\\u")
      guard pieces.first == "",
        pieces.dropFirst().allSatisfy({ $0.count == 4 && UInt16($0, radix: 16) != nil })
      else { throw ToolFailure("请输入连续的 \\uXXXX 序列") }
      let units = pieces.dropFirst().compactMap { UInt16($0, radix: 16) }
      let result = String(decoding: units, as: UTF16.self)
      guard Array(result.utf16) == units else { throw ToolFailure("UTF-16 代理项无效") }
      return result
    case .hex:
      if !decode { return bytes.map { String(format: "%02x", $0) }.joined(separator: " ") }
      let digits = Array(input.filter { !$0.isWhitespace })
      guard digits.count.isMultiple(of: 2) else { throw ToolFailure("Hex 必须成对出现") }
      let decoded = try stride(from: 0, to: digits.count, by: 2).map { i -> UInt8 in
        guard let byte = UInt8(String(digits[i...i + 1]), radix: 16) else {
          throw ToolFailure("无效的 Hex 字符")
        }
        return byte
      }
      return try utf8(Data(decoded))
    case .timestamp:
      let fmt = ISO8601DateFormatter()
      let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
      if operation == operations[0] {
        guard let n = Double(raw), n.isFinite, abs(n) < 1e15 else {
          throw ToolFailure("请输入秒或毫秒时间戳")
        }
        return fmt.string(from: Date(timeIntervalSince1970: abs(n) >= 1e11 ? n / 1000 : n))
      }
      let plain = fmt.date(from: raw)
      fmt.formatOptions.insert(.withFractionalSeconds)
      guard let date = plain ?? fmt.date(from: raw) else {
        throw ToolFailure("请输入带时区的 ISO 8601 日期")
      }
      return
        "秒  \(Int64(date.timeIntervalSince1970))\n毫秒  \(Int64((date.timeIntervalSince1970 * 1000).rounded()))"
    case .hash:
      let digest: [UInt8]
      switch operation {
      case "MD5": digest = Array(Insecure.MD5.hash(data: bytes))
      case "SHA1": digest = Array(Insecure.SHA1.hash(data: bytes))
      case "SHA384": digest = Array(SHA384.hash(data: bytes))
      case "SHA512": digest = Array(SHA512.hash(data: bytes))
      case "HMAC-SHA256", "HMAC-SHA512":
        guard !extra.isEmpty else { throw ToolFailure("请输入 HMAC 密钥") }
        let key = SymmetricKey(data: Data(extra.utf8))
        digest =
          operation == "HMAC-SHA256"
          ? Array(HMAC<SHA256>.authenticationCode(for: bytes, using: key))
          : Array(HMAC<SHA512>.authenticationCode(for: bytes, using: key))
      default: digest = Array(SHA256.hash(data: bytes))
      }
      return digest.map { String(format: "%02x", $0) }.joined()
    case .jwt:
      let parts = input.trimmingCharacters(in: .whitespacesAndNewlines).split(
        separator: ".", omittingEmptySubsequences: false)
      guard parts.count == 3 else { throw ToolFailure("JWT 需要三个部分") }
      let values = try parts.prefix(2).map { part -> Any in
        var b64 = part.replacingOccurrences(of: "-", with: "+").replacingOccurrences(
          of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let data = Data(base64Encoded: b64) else { throw ToolFailure("无效的 JWT 编码") }
        return try JSONSerialization.jsonObject(with: data)
      }
      return try jsonData(["header": values[0], "payload": values[1]], pretty: true)
    case .uuid:
      if operation == "UUID" { return UUID().uuidString.lowercased() }
      guard let count = Int(extra.isEmpty ? "32" : extra), (1...4096).contains(count) else {
        throw ToolFailure("长度范围为 1 至 4096")
      }
      let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
      return String((0..<count).map { _ in alphabet.randomElement()! })
    case .text:
      let lines = input.components(separatedBy: "\n")
      switch operation {
      case "按行去重":
        var seen = Set<String>()
        return lines.filter { seen.insert($0).inserted }.joined(separator: "\n")
      case "按行排序": return lines.sorted().joined(separator: "\n")
      case "大写": return input.uppercased()
      case "小写": return input.lowercased()
      case "清理空白": return input.trimmingCharacters(in: .whitespacesAndNewlines)
      default: return "\(lines.count) 行 · \(input.count) 个字符 · \(bytes.count) 字节"
      }
    case .diff:
      let left = input.components(separatedBy: "\n")
      let right = extra.components(separatedBy: "\n")
      let diff = right.difference(from: left)
      var removed = Set<Int>()
      var inserted = Set<Int>()
      for change in diff {
        switch change {
        case .remove(let i, _, _): removed.insert(i)
        case .insert(let i, _, _): inserted.insert(i)
        }
      }
      var a = 0
      var b = 0
      var output: [String] = []
      while a < left.count || b < right.count {
        if removed.contains(a) {
          output.append("− " + left[a])
          a += 1
        } else if inserted.contains(b) {
          output.append("+ " + right[b])
          b += 1
        } else {
          output.append("  " + right[b])
          a += 1
          b += 1
        }
      }
      return output.joined(separator: "\n")
    case .regex:
      guard !extra.isEmpty else { throw ToolFailure("请输入正则表达式") }
      let re = try NSRegularExpression(pattern: extra)
      let range = NSRange(input.startIndex..., in: input)
      if operation == "替换" {
        return re.stringByReplacingMatches(in: input, range: range, withTemplate: replacement)
      }
      let matches = re.matches(in: input, range: range)
      if matches.isEmpty { return "没有匹配项" }
      return matches.map { match in
        (0..<match.numberOfRanges).compactMap { i in
          Range(match.range(at: i), in: input).map { String(input[$0]) }
        }.joined(separator: "  |  ")
      }.joined(separator: "\n")
    }
  }
}
