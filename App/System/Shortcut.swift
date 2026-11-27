import Carbon
import SwiftUI

struct Shortcut: Codable, Equatable {
  let code: UInt32
  let modifiers: UInt32
  let label: String
  static let launcher = Shortcut(
    code: UInt32(kVK_Space), modifiers: UInt32(optionKey), label: "⌥ Space")
  static let clipboard = Shortcut(
    code: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | shiftKey), label: "⌘ ⇧ C")
  static func saved(_ id: UInt32) -> Shortcut {
    guard let data = UserDefaults.standard.data(forKey: "shortcut.\(id)"),
      let value = try? JSONDecoder().decode(Self.self, from: data)
    else { return id == 1 ? .launcher : .clipboard }
    return value
  }
}

struct ShortcutRecorder: NSViewRepresentable {
  let shortcut: Shortcut
  let change: (Shortcut) -> Void
  func makeNSView(context: Context) -> Recorder {
    let button = Recorder()
    button.bezelStyle = .rounded
    button.target = button
    button.action = #selector(Recorder.begin)
    button.toolTip = "点击后按下新的组合键，Esc 取消"
    return button
  }
  func updateNSView(_ button: Recorder, context: Context) {
    button.value = shortcut
    button.change = change
    if !button.recording { button.title = shortcut.label }
  }
  final class Recorder: NSButton {
    var value = Shortcut.launcher, recording = false
    var change: ((Shortcut) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    @objc func begin() {
      if window?.makeFirstResponder(self) == true {
        recording = true
        title = "请按组合键…"
      }
    }
    override func resignFirstResponder() -> Bool {
      recording = false
      title = value.label
      return super.resignFirstResponder()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
      if recording && event.type == .keyDown {
        keyDown(with: event)
        return true
      }
      return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
      guard recording else {
        super.keyDown(with: event)
        return
      }
      if event.keyCode == UInt16(kVK_Escape) {
        window?.makeFirstResponder(nil)
        return
      }
      let flags = event.modifierFlags
      guard !flags.intersection([.command, .option, .control]).isEmpty else {
        NSSound.beep()
        return
      }
      var modifiers = 0
      var symbols = ""
      for (flag, mask, symbol) in [
        (NSEvent.ModifierFlags.control, controlKey, "⌃"), (.option, optionKey, "⌥"),
        (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘"),
      ] where flags.contains(flag) {
        modifiers |= mask
        symbols += symbol + " "
      }
      let key =
        event.keyCode == UInt16(kVK_Space)
        ? "Space" : event.charactersIgnoringModifiers?.uppercased() ?? ""
      guard !key.isEmpty else {
        NSSound.beep()
        return
      }
      window?.makeFirstResponder(nil)
      change?(
        Shortcut(code: UInt32(event.keyCode), modifiers: UInt32(modifiers), label: symbols + key))
    }
  }
}
