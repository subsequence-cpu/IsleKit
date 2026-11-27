// swift-tools-version: 6.0
import PackageDescription

let modules = ["PluginKit", "DesignSystem", "DeveloperToolsPlugin", "ClipboardPlugin", "FinderActionsPlugin", "MousePlugin"]
let package = Package(
    name: "IsleKit", platforms: [.macOS(.v13)],
    dependencies: [.package(path: "Packages/IsleKitModules")],
    targets: [.executableTarget(name: "IsleKit", dependencies: modules.map { .product(name: $0, package: "IsleKitModules") },
                                path: "App", exclude: ["Notices", "Assets.xcassets", "Info.plist", "IsleKit.entitlements"])]
)
