import DesignSystem
import PluginKit
import ServiceManagement
import SwiftUI

struct Preferences: View {
  @ObservedObject var desktop: Desktop
  @ViewState private var login = SMAppService.mainApp.status == .enabled
  @ViewState private var status = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Toggle(
        "登录时启动岛匣",
        isOn: Binding(
          get: { login },
          set: { wanted in
            do {
              if wanted {
                try SMAppService.mainApp.register()
              } else {
                try SMAppService.mainApp.unregister()
              }
              login = SMAppService.mainApp.status == .enabled
              status = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置的登录项中允许岛匣。" : ""
            } catch { status = error.localizedDescription }
          }))
      Divider()
      Text("快捷键").font(.headline)
      HStack {
        Text("启动台搜索")
        ShortcutRecorder(shortcut: desktop.launcherKey) { desktop.changeShortcut($0, id: 1) }.frame(
          width: 128, height: 27)
      }
      Text("运行工具         ⌘ ↵")
      if !desktop.shortcutError.isEmpty { Text(desktop.shortcutError) }
      if !status.isEmpty { Text(status) }
    }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(
      paper, in: RoundedRectangle(cornerRadius: 16))
  }
}
