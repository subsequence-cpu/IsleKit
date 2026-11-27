import Cocoa
import FinderActionsShared
import FinderSync

@objc(IsleKitFinderSync)
final class FinderSync: FIFinderSync {
  override init() {
    super.init()
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(reload),
      name: FinderPreferences.notification, object: nil)
    reload()
  }
  @objc private func reload() {
    FinderPreferences.defaults.synchronize()
    let paths = FinderPreferences.defaults.bool(forKey: "enabled") ? FinderPreferences.folders : []
    FIFinderSyncController.default().directoryURLs = Set(paths.map { URL(fileURLWithPath: $0) })
  }
  override func menu(for kind: FIMenuKind) -> NSMenu? {
    guard FinderPreferences.defaults.bool(forKey: "enabled") else { return nil }
    let finder = FIFinderSyncController.default()
    let urls: [URL]
    switch kind {
    case .contextualMenuForItems: urls = finder.selectedItemURLs() ?? []
    case .contextualMenuForContainer: urls = finder.targetedURL().map { [$0] } ?? []
    default: return nil
    }
    guard (1...32).contains(urls.count), urls.allSatisfy(\.isFileURL) else { return nil }
    let menu = NSMenu()
    for action in FinderAction.allCases {
      if action == .create && (urls.count != 1 || !urls[0].hasDirectoryPath) { continue }
      if action == .rename && (kind != .contextualMenuForItems || urls.count != 1) { continue }
      let item = menu.addItem(
        withTitle: action.title, action: #selector(invoke(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = action.link(paths: urls.map(\.path))
    }
    return menu
  }
  @objc private func invoke(_ item: NSMenuItem) {
    if let url = item.representedObject as? URL { NSWorkspace.shared.open(url) }
  }
}
