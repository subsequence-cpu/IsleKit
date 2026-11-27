import Foundation

func loadClipboardKey(existing: Bool) throws -> Data {
  let service = Bundle.main.bundleURL.appendingPathComponent("Contents/XPCServices/ClipboardKey.xpc")
  // Unbundled developer runs and ad-hoc previews use their own Keychain access.
  guard FileManager.default.fileExists(atPath: service.path),
    let requirement = try clipboardPeerRequirement(identifier: clipboardServiceID)
  else { return try readClipboardKey(existing: existing) }

  let connection = NSXPCConnection(serviceName: clipboardServiceID)
  connection.remoteObjectInterface = NSXPCInterface(with: ClipboardKeyProtocol.self)
  connection.setCodeSigningRequirement(requirement)
  connection.resume()
  defer { connection.invalidate() }
  var result: Result<Data, Error> = .failure(ClipboardKeyError("剪贴板密钥服务未响应"))
  let proxy = connection.synchronousRemoteObjectProxyWithErrorHandler { result = .failure($0) }
  (proxy as? ClipboardKeyProtocol)?.loadKey(existing: existing) { key, message in
    if let key, key.count == 32 {
      result = .success(key)
    } else {
      result = .failure(ClipboardKeyError(message ?? "无法读取剪贴板密钥"))
    }
  }
  return try result.get()
}
