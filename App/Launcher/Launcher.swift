import DesignSystem
import PluginKit
import SwiftUI

extension Shell {
  var home: some View {
    let all = registry.commands
    let recent = registry.recent.compactMap { id in all.first { $0.id == id } }
    let featured = recent.first ?? all.first
    let pinned = registry.favorites.compactMap { id in all.first { $0.id == id } }
    let quick =
      pinned.isEmpty
      ? ["clipboard", "developer-tools.timestamp", "developer-tools.diff"].compactMap { id in
        all.first { $0.id == id }
      } : pinned
    return VStack(alignment: .leading, spacing: 14) {
      if let featured {
        HStack {
          VStack(alignment: .leading, spacing: 8) {
            if !recent.isEmpty { Text("上次使用").font(.caption) }
            Text(featured.title).font(.title.bold())
            Button(recent.isEmpty ? "打开工具 →" : "继续使用 →") { desktop.go(featured.id) }.buttonStyle(
              .borderedProminent)
          }
          Spacer()
          ZStack {
            Artwork(name: "terminal", size: 120).rotationEffect(.degrees(-6))
            Artwork(name: "keyboard", size: 74).rotationEffect(.degrees(8)).offset(x: 34, y: 33)
          }.padding(.trailing, 20)
        }.padding(.horizontal, 24).frame(height: 146).background(
          ink(0xF9ECC8), in: RoundedRectangle(cornerRadius: 20))
      } else {
        Button("启用插件以开始使用") { desktop.go("plugins") }
      }
      if !quick.isEmpty {
        Text(pinned.isEmpty ? "常用工具" : "已收藏").font(.headline)
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: min(3, quick.count)),
          spacing: 12
        ) {
          ForEach(Array(quick.enumerated()), id: \.element.id) { i, command in
            Button {
              desktop.go(command.id)
            } label: {
              VStack(alignment: .leading) {
                Artwork(name: command.icon, size: 40)
                Text(command.title).font(.headline).lineLimit(1)
                if command.group != command.title { Text(command.group).font(.caption).lineLimit(1) }
              }
              .padding(14).frame(maxWidth: .infinity, alignment: .leading)
              .frame(height: 108, alignment: .topLeading).background(
                [ink(0xF9E7C7), ink(0xE4E6F6), mint][i % 3], in: RoundedRectangle(cornerRadius: 15))
            }.buttonStyle(.plain)
          }
        }
      }
      if !recent.isEmpty {
        Text("最近使用").font(.headline)
        VStack(alignment: .leading) {
          ForEach(recent) { commandRow($0) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(
          paper, in: RoundedRectangle(cornerRadius: 14))
      }
    }.padding(.trailing, 12)
  }
}
