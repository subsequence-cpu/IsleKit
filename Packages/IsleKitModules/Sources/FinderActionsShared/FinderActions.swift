import Foundation

public enum FinderAction: String, CaseIterable, Sendable {
  case create = "new-file"
  case rename
  case editor = "vscode"
  public var title: String {
    switch self {
    case .create: "新增文件…"
    case .rename: "重命名…"
    case .editor: "使用 VS Code 打开"
    }
  }
  public func link(paths: [String]) -> URL? {
    var parts = URLComponents()
    parts.scheme = "islekit"
    parts.host = "finder"
    parts.path = "/" + rawValue
    parts.queryItems = paths.map { URLQueryItem(name: "path", value: $0) }
    return parts.url
  }
  public static func parse(_ url: URL) -> (FinderAction, [URL])? {
    guard url.scheme == "islekit", url.host == "finder", url.absoluteString.utf8.count <= 65536,
      let action = FinderAction(rawValue: String(url.path.dropFirst())),
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
      (1...32).contains(items.count)
    else { return nil }
    let paths = items.compactMap { item -> URL? in
      guard item.name == "path", let value = item.value, value.hasPrefix("/"), !value.contains("\0")
      else { return nil }
      return URL(fileURLWithPath: value).standardizedFileURL
    }
    guard paths.count == items.count, action == .editor || paths.count == 1 else { return nil }
    return (action, paths)
  }
}

public enum FinderPreferences {
  public static var defaults: UserDefaults {
    UserDefaults(suiteName: "group.io.github.subsequence-cpu.IsleKit")!
  }
  public static let notification = Notification.Name(
    "io.github.subsequence-cpu.IsleKit.finder.changed")
  public static var folders: [String] { defaults.stringArray(forKey: "folders") ?? [] }
  public static func allows(_ path: URL) -> Bool {
    let target = path.resolvingSymlinksInPath().standardizedFileURL.path
    return folders.contains { folder in
      let root = URL(fileURLWithPath: folder).resolvingSymlinksInPath().standardizedFileURL.path
      return target == root || target.hasPrefix(root == "/" ? "/" : root + "/")
    }
  }
}
