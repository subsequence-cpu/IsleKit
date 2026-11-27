import FinderActionsShared
import FinderSync
import PluginKit
import SwiftUI

@MainActor public final class FinderActions: ObservableObject, IslandPlugin {
  public init() {}
  public let id = "finder-actions", title = "Finder 扩展", icon = "folder",
    summary = "为所选目录添加新建文件、重命名与编辑器菜单。"
  @Published var folders = FinderPreferences.folders
  public func setEnabled(_ enabled: Bool) {
    FinderPreferences.defaults.set(enabled, forKey: "enabled")
    notify()
  }
  func save() {
    FinderPreferences.defaults.set(folders, forKey: "folders")
    notify()
  }
  private func notify() {
    FinderPreferences.defaults.synchronize()
    DistributedNotificationCenter.default().post(name: FinderPreferences.notification, object: nil)
  }
  public func handle(_ url: URL) {
    guard FinderPreferences.defaults.bool(forKey: "enabled"),
      let (action, paths) = FinderAction.parse(url),
      paths.allSatisfy(FinderPreferences.allows), let first = paths.first
    else { return }
    NSApp.activate(ignoringOtherApps: true)
    do {
      switch action {
      case .create:
        let panel = NSSavePanel()
        panel.directoryURL = first
        panel.nameFieldStringValue = "未命名.txt"
        if panel.runModal() == .OK, let dest = panel.url {
          try Data().write(to: dest, options: .withoutOverwriting)
        }
      case .rename:
        let dialog = NSAlert()
        dialog.messageText = "重命名“\(first.lastPathComponent)”"
        let field = NSTextField(string: first.lastPathComponent)
        field.frame.size = NSSize(width: 310, height: 25)
        dialog.accessoryView = field
        dialog.addButton(withTitle: "重命名")
        dialog.addButton(withTitle: "取消")
        guard dialog.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue
        guard !["", ".", ".."].contains(name), !name.contains("/") else {
          throw CocoaError(.fileWriteInvalidFileName)
        }
        let dest = first.deletingLastPathComponent().appendingPathComponent(name)
        if dest.path != first.path { try FileManager.default.moveItem(at: first, to: dest) }
      case .editor:
        guard
          let editor = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.microsoft.VSCode")
        else { throw CocoaError(.fileNoSuchFile) }
        let dialog = NSAlert()
        dialog.messageText = "在 VS Code 中打开所选项目？"
        dialog.informativeText = paths.map(\.path).joined(separator: "\n")
        dialog.addButton(withTitle: "打开")
        dialog.addButton(withTitle: "取消")
        guard dialog.runModal() == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.open(paths, withApplicationAt: editor, configuration: .init()) {
          _, error in
          if let error { Task { @MainActor in NSApp.presentError(error) } }
        }
      }
    } catch { NSApp.presentError(error) }
  }
  public func page(command: String?) -> AnyView { AnyView(FinderPage(model: self)) }
}
private struct FinderPage: View {
  @ObservedObject var model: FinderActions
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("访达菜单目录").font(.headline)
      ForEach(model.folders, id: \.self) { folder in
        HStack {
          Image(systemName: "folder")
          Text(folder)
          Spacer()
          Button("移除") {
            model.folders.removeAll { $0 == folder }
            model.save()
          }
        }
      }
      HStack {
        Button("添加目录…") {
          let panel = NSOpenPanel()
          panel.canChooseFiles = false
          panel.canChooseDirectories = true
          if panel.runModal() == .OK, let url = panel.url, !model.folders.contains(url.path) {
            model.folders.append(url.path)
            model.save()
          }
        }
        Button("管理系统扩展…") { FIFinderSyncController.showExtensionManagementInterface() }
      }
    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(
      .background, in: RoundedRectangle(cornerRadius: 16))
  }
}
