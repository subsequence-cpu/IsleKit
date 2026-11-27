import PluginKit
import SwiftUI

@main struct IsleKitApp: App {
  @StateObject private var desktop = Desktop()
  var body: some Scene {
    Window("岛匣", id: "workspace") {
      Shell(desktop: desktop, registry: desktop.registry)
        .onOpenURL { url in
          if desktop.registry.enabled.contains(desktop.finder.id) { desktop.finder.handle(url) }
        }
    }.defaultSize(width: 1030, height: 650)
      .commands {
        CommandGroup(after: .appSettings) {
          Button("岛匣设置…") {
            desktop.go("settings")
            desktop.show()
          }.keyboardShortcut(",", modifiers: .command)
        }
        CommandMenu("工具") {
          Button("搜索工具") { desktop.show(search: true) }.keyboardShortcut("k", modifiers: .command)
        }
      }
    MenuBarExtra("岛匣", systemImage: "shippingbox") {
      MenuActions(desktop: desktop, registry: desktop.registry)
    }
  }
}
private struct MenuActions: View {
  @ObservedObject var desktop: Desktop
  @ObservedObject var registry: PluginRegistry
  @Environment(\.openWindow) var open
  var body: some View {
    Button("打开岛匣") {
      open(id: "workspace")
      desktop.show()
    }
    if registry.enabled.contains("clipboard") { Button("剪贴板历史") { desktop.showClipboard() } }
    Divider()
    Button("退出岛匣") { NSApp.terminate(nil) }
  }
}
