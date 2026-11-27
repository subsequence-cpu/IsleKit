import DesignSystem
import PluginKit
import SwiftUI

extension Shell {
  var plugins: some View {
    VStack(alignment: .leading, spacing: 14) {
      Picker("显示插件", selection: $enabledOnly) {
        Text("全部  \(registry.plugins.count)").tag(false)
        Text("已启用  \(registry.enabled.count)").tag(true)
      }.labelsHidden().pickerStyle(.segmented).fixedSize()
      VStack(spacing: 0) {
        ForEach(registry.plugins.map(\.id), id: \.self) { id in
          if let plugin = registry.plugins.first(where: { $0.id == id }),
            !enabledOnly || registry.enabled.contains(id)
          {
            HStack(spacing: 15) {
              let details = HStack(spacing: 15) {
                Artwork(name: plugin.icon, size: 43)
                VStack(alignment: .leading, spacing: 5) {
                  Text(plugin.title).font(.headline)
                  Text(plugin.summary).font(.callout)
                }
                Spacer()
              }
              if id == desktop.mouse.id {
                Button { desktop.go(id) } label: {
                  details.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(plugin.title)
                  .accessibilityIdentifier("mouse.pluginDetails")
              } else {
                details
              }
              Toggle(
                plugin.title,
                isOn: Binding(
                  get: { registry.enabled.contains(id) },
                  set: { value in
                    if value != registry.enabled.contains(id) { desktop.toggle(plugin) }
                  })
              ).labelsHidden().toggleStyle(.switch)
            }.padding(16)
            Divider()
          }
        }
      }.background(paper, in: RoundedRectangle(cornerRadius: 16))
    }
  }
}
