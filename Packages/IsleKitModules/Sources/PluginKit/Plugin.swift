import SwiftUI

// Use the back-deployable property wrapper with Command Line Tools as well as Xcode.
public typealias ViewState<Value> = SwiftUI.State<Value>

public struct ToolCommand: Identifiable, Equatable, Sendable {
  public let id: String, title: String, icon: String, group: String
  public init(_ id: String, _ title: String, _ icon: String, _ group: String) {
    self.id = id
    self.title = title
    self.icon = icon
    self.group = group
  }
}

@MainActor public protocol IslandPlugin: AnyObject {
  var id: String { get }
  var title: String { get }
  var icon: String { get }
  var summary: String { get }
  var commands: [ToolCommand] { get }
  func setEnabled(_ enabled: Bool)
  func page(command: String?) -> AnyView
}

extension IslandPlugin {
  public var commands: [ToolCommand] { [ToolCommand(id, title, icon, title)] }
  public func setEnabled(_ enabled: Bool) {}
}

@MainActor public final class PluginRegistry: ObservableObject {
  public let plugins: [any IslandPlugin]
  private let defaults: UserDefaults
  @Published public private(set) var enabled: Set<String>
  @Published public private(set) var recent: [String]
  @Published public private(set) var favorites: [String]

  public init(_ plugins: [any IslandPlugin], defaults: UserDefaults = .standard) {
    self.plugins = plugins
    self.defaults = defaults
    enabled = Set(
      defaults.stringArray(forKey: "plugins.enabled")
        ?? plugins.filter { $0.id != "mouse" }.map(\.id))
    recent = defaults.stringArray(forKey: "commands.recent") ?? []
    favorites = defaults.stringArray(forKey: "commands.favorites") ?? []
    for plugin in plugins { plugin.setEnabled(enabled.contains(plugin.id)) }
  }
  public var commands: [ToolCommand] {
    plugins.filter { enabled.contains($0.id) }.flatMap(\.commands)
  }
  public func owner(of command: String) -> (any IslandPlugin)? {
    plugins.first { enabled.contains($0.id) && $0.commands.contains { $0.id == command } }
  }
  public func toggle(_ plugin: any IslandPlugin) {
    if enabled.contains(plugin.id) { enabled.remove(plugin.id) } else { enabled.insert(plugin.id) }
    defaults.set(Array(enabled), forKey: "plugins.enabled")
    plugin.setEnabled(enabled.contains(plugin.id))
  }
  public func record(_ id: String) {
    guard owner(of: id) != nil else { return }
    recent = Array(([id] + recent.filter { $0 != id }).prefix(16))
    defaults.set(recent, forKey: "commands.recent")
  }
  public func favorite(_ id: String) {
    if favorites.contains(id) { favorites.removeAll { $0 == id } } else { favorites.append(id) }
    defaults.set(favorites, forKey: "commands.favorites")
  }
}
