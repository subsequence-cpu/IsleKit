import Carbon
import ClipboardPlugin
import DeveloperToolsPlugin
import FinderActionsPlugin
import MousePlugin
import PluginKit
import SwiftUI

private final class ClipPanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

@MainActor final class Desktop: ObservableObject {
  let clipboard = Clipboard(), finder = FinderActions()
  let mouse = Mouse()
  let registry: PluginRegistry
  @Published var route = "home"
  @Published var query = ""
  @Published var searchFocus = 0
  @Published var shortcutError = ""
  private var handler: EventHandlerRef?
  private var hotkeys: [UInt32: EventHotKeyRef] = [:]
  @Published var launcherKey = Shortcut.saved(1)
  @Published var clipboardKey = Shortcut.saved(2)
  private var panel: NSPanel?
  var openWindow: (() -> Void)?

  init() { registry = PluginRegistry([DeveloperTools(), clipboard, finder, mouse]) }

  func go(_ id: String) {
    query = ""
    if registry.owner(of: id) != nil {
      route = id
      registry.record(id)
    } else if ["home", "plugins", "settings", mouse.id].contains(id)
      || registry.enabled.contains(id)
    {
      route = id
    } else {
      route = "home"
    }
  }
  func toggle(_ plugin: any IslandPlugin) {
    let active = route == plugin.id || registry.owner(of: route)?.id == plugin.id
    registry.toggle(plugin)
    if !registry.enabled.contains(plugin.id) {
      if active && plugin.id != mouse.id { go("home") }
      if plugin.id == clipboard.id { panel?.orderOut(nil) }
    }
    if plugin.id == clipboard.id { registerHotkeys() }
  }
  func show(search: Bool = false) {
    openWindow?()
    NSApp.activate(ignoringOtherApps: true)
    if search {
      go("home")
      searchFocus += 1
    }
  }
  func showClipboard() {
    guard registry.enabled.contains(clipboard.id) else { return }
    if panel?.isVisible == true {
      panel?.orderOut(nil)
      return
    }
    if panel == nil {
      let window = ClipPanel(
        contentRect: .init(x: 0, y: 0, width: 530, height: 420),
        styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered,
        defer: false)
      window.title = "岛匣 · 剪贴板"
      window.level = .floating
      window.isReleasedWhenClosed = false
      window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
      window.contentView = NSHostingView(
        rootView: clipboard.panel(in: window).padding(8).background(WindowEditingDismissal()))
      window.center()
      panel = window
    }
    panel?.makeKeyAndOrderFront(nil)
  }
  func registerHotkeys() {
    for hotkey in hotkeys.values { UnregisterEventHotKey(hotkey) }
    hotkeys.removeAll()
    shortcutError = ""
    if handler == nil {
      var spec = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
      let status = InstallEventHandler(
        GetApplicationEventTarget(),
        { _, event, ref in
          guard let ref, let event else { return OSStatus(eventNotHandledErr) }
          var key = EventHotKeyID()
          let err = GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
            MemoryLayout<EventHotKeyID>.size, nil, &key)
          guard err == noErr, key.signature == 0x4953_4C45 else {
            return OSStatus(eventNotHandledErr)
          }
          let model = Unmanaged<Desktop>.fromOpaque(ref).takeUnretainedValue()
          MainActor.assumeIsolated {
            if key.id == 1 { model.show(search: true) } else { model.showClipboard() }
          }
          return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
      guard status == noErr else {
        shortcutError = "快捷键处理器注册失败（\(status)）"
        return
      }
    }
    _ = install(launcherKey, id: 1)
    if registry.enabled.contains(clipboard.id) { _ = install(clipboardKey, id: 2) }
  }

  private func install(_ key: Shortcut, id: UInt32) -> Bool {
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      key.code, key.modifiers, EventHotKeyID(signature: 0x4953_4C45, id: id),
      GetApplicationEventTarget(), 0, &ref)
    guard status == noErr, let ref else {
      shortcutError = "\(key.label) 无法注册，可能已被占用（\(status)）"
      return false
    }
    if let old = hotkeys.updateValue(ref, forKey: id) { UnregisterEventHotKey(old) }
    return true
  }

  func changeShortcut(_ value: Shortcut, id: UInt32) {
    let current = id == 1 ? launcherKey : clipboardKey
    let other = id == 1 ? clipboardKey : launcherKey
    if current.code == value.code && current.modifiers == value.modifiers { return }
    guard other.code != value.code || other.modifiers != value.modifiers else {
      shortcutError = "两个全局快捷键需要各自的组合"
      return
    }
    guard install(value, id: id) else { return }
    if id == 1 {
      launcherKey = value
    } else {
      clipboardKey = value
      if !registry.enabled.contains(clipboard.id), let ref = hotkeys.removeValue(forKey: id) {
        UnregisterEventHotKey(ref)
      }
    }
    UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: "shortcut.\(id)")
    shortcutError = ""
  }
}
