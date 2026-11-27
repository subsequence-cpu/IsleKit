import CryptoKit
import Foundation
import Security

let clipboardAppID = "io.github.subsequence-cpu.IsleKit"
let clipboardServiceID = clipboardAppID + ".ClipboardKey"

struct ClipboardKeyError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

@objc(IsleKitClipboardKeyProtocol)
protocol ClipboardKeyProtocol {
  func loadKey(existing: Bool, reply: @escaping (Data?, String?) -> Void)
}

// Pin both ends of the connection to the signing certificate of the running process.
func clipboardPeerRequirement(identifier: String) throws -> String? {
  var code: SecCode?
  var signedCode: SecStaticCode?
  var info: CFDictionary?
  guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
    SecCodeCopyStaticCode(code, [], &signedCode) == errSecSuccess, let signedCode,
    SecCodeCopySigningInformation(signedCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
      == errSecSuccess, let fields = info as? [String: Any]
  else { throw ClipboardKeyError("无法验证剪贴板组件的签名") }
  guard let leaf = (fields[kSecCodeInfoCertificates as String] as? [SecCertificate])?.first
  else { return nil } // Ad-hoc preview builds have no shared signer.
  let der = SecCertificateCopyData(leaf) as Data
  let pin = Insecure.SHA1.hash(data: der).map { String(format: "%02x", $0) }.joined()
  return "identifier \"\(identifier)\" and certificate leaf = H\"\(pin)\""
}

func readClipboardKey(existing: Bool) throws -> Data {
  let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "IsleKit.clipboard",
    kSecAttrAccount as String: "sqlcipher",
  ]
  var read = query
  var result: CFTypeRef?
  read[kSecReturnData as String] = true
  let status = SecItemCopyMatching(read as CFDictionary, &result)
  if status == errSecSuccess {
    guard let key = result as? Data, key.count == 32 else {
      throw ClipboardKeyError("数据库密钥长度无效")
    }
    return key
  }
  guard status == errSecItemNotFound && !existing else {
    throw ClipboardKeyError("无法从钥匙串读取历史密钥（\(status)）")
  }
  var bytes = [UInt8](repeating: 0, count: 32)
  guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
    throw ClipboardKeyError("密钥生成失败")
  }
  var item = query
  item[kSecValueData as String] = Data(bytes)
  item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
  let added = SecItemAdd(item as CFDictionary, nil)
  if added == errSecDuplicateItem { return try readClipboardKey(existing: true) }
  guard added == errSecSuccess else { throw ClipboardKeyError("无法保存历史密钥（\(added)）") }
  return Data(bytes)
}
