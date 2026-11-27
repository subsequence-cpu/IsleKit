import DesignSystem
import PluginKit
import SwiftUI

struct Shell: View {
  @ObservedObject var desktop: Desktop
  @ObservedObject var registry: PluginRegistry
  @Environment(\.openWindow) var open
  @FocusState private var focus: Bool
  @ViewState var enabledOnly = false
  var plugin: (any IslandPlugin)? {
    registry.owner(of: desktop.route)
      ?? registry.plugins.first {
        $0.id == desktop.route && (registry.enabled.contains($0.id) || $0.id == desktop.mouse.id)
      }
  }
  var current: ToolCommand? { registry.commands.first { $0.id == desktop.route } }
  var heading: String {
    switch desktop.route {
    case "plugins": "插件管理"
    case "settings": "设置"
    default: current?.title ?? plugin?.title ?? "启动台"
    }
  }
  var body: some View {
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          AppMark(size: 43)
          Text("岛匣").font(.title2.bold())
        }.padding(.bottom, 16)
        nav("启动台", "home", "home")
        nav("插件管理", "puzzle", "plugins")
        Text("已启用").font(.caption).padding(.top, 18).padding(.leading, 12)
        ForEach(registry.plugins.map(\.id), id: \.self) { id in
          if registry.enabled.contains(id),
            let item = registry.plugins.first(where: { $0.id == id })
          {
            nav(item.title, item.icon, id)
          }
        }
        Spacer()
        Divider()
        nav("设置", "settings", "settings")
      }.padding(14).frame(width: 183).background(rail)
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          RibbonTitle(title: desktop.query.isEmpty ? heading : "搜索结果")
          if desktop.route == "home" {
            Spacer()
            HStack {
              Image(systemName: "magnifyingglass")
              TextField("搜索工具或命令   ⌘ K", text: $desktop.query).textFieldStyle(.plain).focused($focus)
                .onSubmit {
                  if let first = matches.first {
                    desktop.go(first.id)
                    focus = false
                  }
                }
            }.padding(8).frame(width: 220).background(rail, in: Capsule())
          }
        }
        if !desktop.query.isEmpty {
          ScrollView {
            VStack {
              ForEach(matches) { commandRow($0) }
              if matches.isEmpty { Text("没有匹配的工具") }
            }.padding()
          }.background(paper, in: RoundedRectangle(cornerRadius: 14))
        } else if desktop.route == desktop.mouse.id {
          ScrollView {
            desktop.mouse.page(command: nil).padding(16)
              .background(paper, in: RoundedRectangle(cornerRadius: 16))
          }
        } else if let plugin {
          if desktop.route == "developer-tools" {
            ScrollView { VStack { ForEach(plugin.commands) { commandRow($0) } }.padding() }
              .background(paper, in: RoundedRectangle(cornerRadius: 14))
          } else if plugin.id == desktop.clipboard.id {
            VStack(alignment: .leading, spacing: 10) {
              HStack {
                Text("浮窗快捷键")
                ShortcutRecorder(shortcut: desktop.clipboardKey) {
                  desktop.changeShortcut($0, id: 2)
                }
                .frame(width: 128, height: 27)
              }
              if !desktop.shortcutError.isEmpty { Text(desktop.shortcutError).font(.callout) }
              plugin.page(command: desktop.route)
            }
          } else {
            plugin.page(command: desktop.route).id(desktop.route)
          }
        } else {
          ScrollView {
            VStack(alignment: .leading, spacing: 15) {
              switch desktop.route {
              case "plugins": plugins
              case "settings": Preferences(desktop: desktop)
              default: home
              }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
          }
        }
        Spacer(minLength: 0)
      }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { DotPaper() }
    }.foregroundStyle(DesignSystem.text).tint(pine).preferredColorScheme(.light).frame(
      minWidth: 820, minHeight: 520
    )
    .background(WindowEditingDismissal())
    .onAppear {
      desktop.openWindow = { open(id: "workspace") }
      desktop.registerHotkeys()
    }
    .onChange(of: desktop.searchFocus) { _ in focus = true }
  }
  var matches: [ToolCommand] {
    registry.commands.filter {
      ($0.title + " " + $0.group + " " + $0.id).localizedCaseInsensitiveContains(
        desktop.query.trimmingCharacters(in: .whitespaces))
    }
  }
  func nav(_ title: String, _ icon: String, _ id: String) -> some View {
    Button {
      desktop.go(id)
    } label: {
      HStack {
        Artwork(name: icon, size: 23)
        Text(title)
        Spacer()
      }.padding(9).contentShape(Rectangle())
    }.buttonStyle(.plain).background(
      desktop.route == id || plugin?.id == id ? mint : .clear,
      in: RoundedRectangle(cornerRadius: 11))
  }
  func commandRow(_ command: ToolCommand) -> some View {
    HStack {
      Button {
        desktop.go(command.id)
      } label: {
        HStack {
          Artwork(name: command.icon, size: 26)
          Text(command.title)
          Spacer()
          if command.group != command.title && desktop.route != "developer-tools" {
            Text(command.group).font(.caption)
          }
        }
        .padding(.vertical, 5).contentShape(Rectangle())
      }.buttonStyle(.plain)
      Button {
        registry.favorite(command.id)
      } label: {
        Image(systemName: registry.favorites.contains(command.id) ? "star.fill" : "star")
      }
      .buttonStyle(.borderless).help("切换收藏")
    }
  }
}
