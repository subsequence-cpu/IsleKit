<p align="center">
  <img src="App/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="96" height="96" alt="岛匣应用图标">
</p>

<h1 align="center">岛匣 · IsleKit</h1>

<p align="center">按下 ⌥ Space 搜工具，按下 ⌘ ⇧ C 找回刚复制的文字或图片。</p>
<p align="center">macOS 13+ · SwiftUI 与 AppKit · <a href="LICENSE">MIT 许可证</a></p>

## 内置插件

从启动台搜索命令、收藏常用工具，或继续上次使用的插件。四个插件可以在「插件管理」中独立启停，具体选项在各自的插件页调整。

| 插件 | 可以做什么 |
| --- | --- |
| **开发工具** | 格式化 JSON，转换时间戳和文本编码，计算摘要与 HMAC，解码 JWT，比较文本或调试正则表达式。 |
| **剪贴板** | 搜索、预览和收藏复制过的文本与图片，点一下即可再次复制。可以暂停记录、排除指定应用，或调整保留天数和数量。 |
| **Finder 扩展** | 在指定目录的访达右键菜单中新建文件、重命名，或用 VS Code 打开所选项目。先在插件中添加目录，再到系统设置启用扩展。 |
| **鼠标增强** | 识别额外按键，绑定调度中心或切换桌面的手势，调整滚动方向、速度和平滑时长。支持的罗技鼠标还可调节硬件 DPI。 |

鼠标增强默认关闭。启用按键映射时，需要在系统设置中授予「辅助功能」权限。访问罗技 HID++ 设备还需要「输入监控」权限。

## 快捷键

| 默认按键 | 操作 | 适用范围 |
| --- | --- | --- |
| <kbd>⌥</kbd> <kbd>Space</kbd> | 打开启动台并聚焦搜索 | 全局，可在「设置」修改 |
| <kbd>⌘</kbd> <kbd>⇧</kbd> <kbd>C</kbd> | 打开或收起剪贴板浮窗 | 全局，可在「剪贴板」修改 |
| <kbd>⌘</kbd> <kbd>K</kbd> | 搜索工具和命令 | 应用内 |
| <kbd>⌘</kbd> <kbd>↵</kbd> | 运行当前工具 | 开发工具页 |

## 从源码运行

在 Mac 上安装带 Swift 6 的 Command Line Tools，克隆仓库后即可构建。首次体验可使用临时签名。

```sh
git clone git@github.com:subsequence-cpu/IsleKit.git
cd IsleKit
SIGN_IDENTITY=- make run
```

日常使用建议固定签名，避免主应用更新后反复授权。Make 默认使用钥匙串里的代码签名证书 `IsleKit Local Development`。使用其他本地证书时，可运行 `SIGN_IDENTITY="证书名称" make run`。使用 Xcode 时，打开 `IsleKit.xcodeproj` 并选择 `IsleKit` scheme。

| 构建命令 | 产物 |
| --- | --- |
| `make app` | 当前架构的 `dist/IsleKit.app`，包含 Finder 扩展与剪贴板密钥服务 |
| `ARCHS="arm64 x86_64" make dmg` | 适用于 Apple 芯片和 Intel Mac 的 `dist/IsleKit.dmg` |

## 本机数据

剪贴板历史由 SQLCipher 加密，数据库位于 `~/Library/Application Support/IsleKit/history.db`。普通记录默认保留 **30 天**，最多 **1,000 条**。密钥保存在 macOS 钥匙串中。本地证书签名的版本通过内置密钥服务读取密钥，首次出现授权提示时，核对「岛匣剪贴板」后可选「始终允许」。更换证书或密钥服务后，系统可能再次询问。

应用设置、收藏的工具和最近使用记录保存在 UserDefaults。开发工具的编辑器输入与 HMAC 密钥仅在内存中处理。

## 工程结构

| 目录 | 职责 |
| --- | --- |
| [App](App/) | SwiftUI 主窗口、启动台、菜单栏与全局快捷键 |
| [Packages/IsleKitModules](Packages/IsleKitModules/) | 插件协议、共用样式、四个内置插件及原生依赖 |
| [Extensions/IsleKitFinderSync](Extensions/IsleKitFinderSync/) | Finder Sync 扩展，与主应用通过 App Group 共享设置 |
| [Services/ClipboardKey](Services/ClipboardKey/) | 剪贴板钥匙串服务 |
| [scripts](scripts/) | 构建应用、嵌入服务与本地签名 |

新增插件时，实现 `IslandPlugin`，再将实例加入宿主的插件注册表。[插件协议](Packages/IsleKitModules/Sources/PluginKit/Plugin.swift) · [宿主注册入口](App/System/Desktop.swift)
