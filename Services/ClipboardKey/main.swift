import Foundation

final class ClipboardKeyService: NSObject, NSXPCListenerDelegate, ClipboardKeyProtocol {
  let clientRequirement: String
  init(clientRequirement: String) { self.clientRequirement = clientRequirement }

  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
    -> Bool
  {
    connection.setCodeSigningRequirement(clientRequirement)
    connection.exportedInterface = NSXPCInterface(with: ClipboardKeyProtocol.self)
    connection.exportedObject = self
    connection.resume()
    return true
  }

  func loadKey(existing: Bool, reply: @escaping (Data?, String?) -> Void) {
    do { reply(try readClipboardKey(existing: existing), nil) }
    catch { reply(nil, error.localizedDescription) }
  }
}

guard let requirement = try clipboardPeerRequirement(identifier: clipboardAppID) else { exit(1) }
let service = ClipboardKeyService(clientRequirement: requirement)
let listener = NSXPCListener.service()
listener.delegate = service
listener.resume()
