// swift-tools-version: 6.0
import PackageDescription

let plugins = ["DeveloperToolsPlugin", "ClipboardPlugin", "FinderActionsPlugin", "MousePlugin"]
let shared = ["PluginKit", "DesignSystem", "FinderActionsShared"]
let package = Package(
    name: "IsleKitModules",
    platforms: [.macOS(.v13)],
    products: (plugins + shared).map { .library(name: $0, targets: [$0]) },
    targets: [
        .target(name: "PluginKit"),
        .target(name: "DesignSystem", resources: [.copy("Art")]),
        .target(name: "FinderActionsShared"),
        .target(name: "CSQLCipher", exclude: ["LICENSE"], cSettings: [
            .define("NDEBUG"), .define("SQLITE_HAS_CODEC"), .define("SQLITE_TEMP_STORE", to: "2"),
            .define("SQLITE_EXTRA_INIT", to: "sqlcipher_extra_init"),
            .define("SQLITE_EXTRA_SHUTDOWN", to: "sqlcipher_extra_shutdown"),
            .define("SQLCIPHER_CRYPTO_CC"), .define("HAVE_USLEEP"), .define("HAVE_STDINT_H")
        ], linkerSettings: [.linkedFramework("Security"), .linkedFramework("CoreFoundation")]),
        .target(name: "DeveloperToolsPlugin", dependencies: ["PluginKit", "DesignSystem"]),
        .target(name: "ClipboardPlugin", dependencies: ["PluginKit", "DesignSystem", "CSQLCipher"]),
        .target(name: "FinderActionsPlugin", dependencies: ["PluginKit", "FinderActionsShared"]),
        .target(name: "CHID", exclude: ["LICENSE"], linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation"), .linkedFramework("AppKit")]),
        .target(name: "MousePlugin", dependencies: ["PluginKit", "DesignSystem", "CHID"])
    ]
)
