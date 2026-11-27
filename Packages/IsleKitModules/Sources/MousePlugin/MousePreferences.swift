import Foundation

enum ButtonAction: String, Codable, CaseIterable {
  case system = "default"
  case back, forward
  case spaces = "mission-control"
  case desktop = "show-desktop"
  case quickLook = "quick-look"
  case disabled = "none"
  case navigationGesture = "direction-gesture"
  var title: String {
    switch self {
    case .system: "系统默认"
    case .back: "后退（⌘ [）"
    case .forward: "前进（⌘ ]）"
    case .spaces: "调度中心与空间手势"
    case .desktop: "显示桌面（F11）"
    case .quickLook: "快速查看（空格）"
    case .disabled: "禁用此按键"
    case .navigationGesture: "文档导航手势"
    }
  }
}

struct MousePreferences: Codable, Equatable {
  var smoothScrolling = true, reverseVertical = false, reverseHorizontal = false
  var scrollSpeed = 1.0, smoothDurationMs = 180
  var middleButton = ButtonAction.system, backButton = ButtonAction.back,
    forwardButton = ButtonAction.forward
  var extraButtons: [String: ButtonAction] = [:]
  var buttons: [Int] { Set([3, 4, 5, 6, 7] + extraButtons.keys.compactMap(Int.init)).sorted() }
  subscript(button: Int) -> ButtonAction {
    get {
      switch button {
      case 3: middleButton
      case 4: backButton
      case 5: forwardButton
      default: extraButtons[String(button)] ?? .system
      }
    }
    set {
      switch button {
      case 3: middleButton = newValue
      case 4: backButton = newValue
      case 5: forwardButton = newValue
      default: extraButtons[String(button)] = newValue
      }
    }
  }
  static func decode(_ data: Data) throws -> Self {
    // Fill omitted fields from the defaults before validating saved settings.
    guard let saved = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let baseline = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Self()))
        as? [String: Any],
      !baseline.keys.allSatisfy({ saved[$0] == nil })
    else { throw CocoaError(.coderInvalidValue) }
    let merged = baseline.merging(saved) { _, stored in stored }
    let value = try JSONDecoder().decode(
      Self.self, from: JSONSerialization.data(withJSONObject: merged))
    guard (0.25...4).contains(value.scrollSpeed), (80...400).contains(value.smoothDurationMs),
      value.extraButtons.keys.allSatisfy({ Int($0).map { (6...32).contains($0) } == true })
    else { throw CocoaError(.coderInvalidValue) }
    return value
  }
  static func load(_ defaults: UserDefaults) -> Self {
    if let data = defaults.data(forKey: "mouse.preferences"), let value = try? decode(data) {
      return value
    }
    var value = Self()
    // The first native release had one side button; preserve its choices on upgrade.
    if let smooth = defaults.object(forKey: "mouse.smooth") as? Bool {
      value.smoothScrolling = smooth
    }
    if let action = defaults.string(forKey: "mouse.side") {
      value.backButton =
        ["方向手势": .navigationGesture, "前进": .forward, "后退": .back][action] ?? .system
    }
    return value
  }
}
