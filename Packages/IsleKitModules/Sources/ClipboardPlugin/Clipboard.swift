import PluginKit
import SwiftUI

@MainActor public final class Clipboard: ObservableObject, IslandPlugin {
  public let id = "clipboard", title = "剪贴板", icon = "clipboard", summary = "搜索、收藏与恢复本机复制过的文本和图片。"
  @Published var items: [HistoryItem] = []
  @Published var message = ""
  @Published var query = ""
  @Published var limit = 100
  let store: History
  private var monitor: Task<Void, Never>?, loadTask: Task<Void, Never>?
  private var changeCount = 0
  public init() {
    let directory = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("IsleKit")
    store = History(url: directory.appendingPathComponent("history.db"))
  }
  public func setEnabled(_ enabled: Bool) {
    monitor?.cancel()
    loadTask?.cancel()
    if !enabled {
      items = []
      query = ""
      return
    }
    changeCount = NSPasteboard.general.changeCount
    monitor = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(650))
        guard !Task.isCancelled, let self else { return }
        await self.capture()
      }
    }
  }
  private func capture() async {
    let board = NSPasteboard.general
    guard changeCount != board.changeCount else { return }
    changeCount = board.changeCount
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: "clips.paused"),
      !(board.types ?? []).contains(where: {
        ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"].contains($0.rawValue)
      })
    else { return }
    let exclusions =
      defaults.string(forKey: "clips.excluded")?.split(separator: ",").map {
        $0.trimmingCharacters(in: .whitespaces)
      } ?? []
    if let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, exclusions.contains(app)
    {
      return
    }
    let kind: String
    let data: Data
    if let png = board.data(forType: .png) {
      kind = "image"
      data = png
    } else if let tiff = board.data(forType: .tiff), let image = NSBitmapImageRep(data: tiff),
      let png = image.representation(using: .png, properties: [:])
    {
      kind = "image"
      data = png
    } else if let string = board.string(forType: .string), !string.isEmpty {
      kind = "text"
      data = Data(string.utf8)
    } else {
      return
    }
    do {
      try await store.add(
        kind: kind, data: data, days: defaults.object(forKey: "clips.days") as? Int ?? 30,
        limit: defaults.object(forKey: "clips.count") as? Int ?? 1000)
      if !Task.isCancelled { refresh() }
    } catch { message = error.localizedDescription }
  }
  func refresh() {
    loadTask?.cancel()
    loadTask = Task {
      do {
        let result = try await store.items(query: query, limit: limit)
        if !Task.isCancelled { items = result }
      } catch { if !Task.isCancelled { message = error.localizedDescription } }
    }
  }
  func clearHistory() async {
    changeCount = NSPasteboard.general.changeCount
    do {
      try await store.removeAll()
      loadTask?.cancel()
      items = []
      limit = 100
      message = ""
      refresh()
    } catch { message = error.localizedDescription }
  }
  func copy(_ item: HistoryItem) async -> Bool {
    do {
      guard let data = try await store.payload(item.id) else {
        message = "记录已删除"
        return false
      }
      let board = NSPasteboard.general
      board.clearContents()
      let ok =
        item.kind == "image"
        ? board.setData(data, forType: .png)
        : board.setString(String(decoding: data, as: UTF8.self), forType: .string)
      changeCount = board.changeCount
      guard ok else {
        message = "写入剪贴板失败"
        return false
      }
      message = ""
      return true
    } catch {
      message = error.localizedDescription
      return false
    }
  }
  public func page(command: String?) -> AnyView { AnyView(ClipList(model: self)) }
  public func panel(in window: NSPanel) -> AnyView {
    AnyView(ClipList(model: self, panel: window))
  }
}

private struct HistoryRowStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View { configuration.label }
}

private struct ClipList: View {
  @ObservedObject var model: Clipboard
  weak var panel: NSPanel?
  @ViewState private var confirmationVisible = false
  @ViewState private var copyTask: Task<Void, Never>?
  @ViewState private var selected: String?
  @ViewState private var confirmingClear = false
  @ViewState private var preferences = false
  @ViewState private var preview: HistoryItem?
  @ViewState private var lastPointer = NSEvent.mouseLocation
  @AppStorage("clips.paused") var paused = false
  @AppStorage("clips.days") var days = 30
  @AppStorage("clips.count") var count = 1000
  @AppStorage("clips.excluded") var excluded = ""
  var body: some View {
    VStack(alignment: .leading) {
      HStack {
        TextField("搜索剪贴板历史", text: $model.query).textFieldStyle(.roundedBorder)
        Toggle("暂停记录", isOn: $paused).toggleStyle(.switch)
        Button {
          preferences.toggle()
        } label: {
          Image(systemName: "slider.horizontal.3")
        }.help("历史设置")
      }
      if preferences {
        HStack(spacing: 12) {
          ClipLimitField(label: "保留", unit: "天", value: $days, limits: 1...365)
          ClipLimitField(label: "普通记录上限", unit: "条", value: $count, limits: 100...10000)
        }
        TextField("排除的应用 Bundle ID，以逗号分隔", text: $excluded)
      }
      if model.items.isEmpty { Text("没有匹配的记录").foregroundStyle(.secondary).padding() }
      HStack(spacing: 10) {
        historyList.frame(minWidth: 145, maxWidth: .infinity)
        if !model.items.isEmpty {
          Divider()
          VStack(alignment: .leading, spacing: 8) {
            Text("内容预览").font(.headline)
            if let item = model.items.first(where: { $0.id == selected }) {
              ClipContent(item: item, store: model.store).id(item.id)
            }
          }.frame(minWidth: 120, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
      }
      .overlay(alignment: .bottom) {
        if confirmationVisible { CopyNotice().padding(.bottom, 12).allowsHitTesting(false) }
      }
      .onChange(of: model.items.map(\.id)) { ids in
        if !ids.contains(selected ?? "") { selected = ids.first }
      }
      HStack {
        Button("预览") { preview = model.items.first { $0.id == selected } }.disabled(selected == nil)
        if model.items.count >= model.limit {
          Button("加载更多") {
            model.limit += 100
            model.refresh()
          }
        }
        Spacer()
        Button("清空记录", role: .destructive) {
          resetConfirmation()
          confirmingClear = true
        }.disabled(model.items.isEmpty && model.query.isEmpty)
        if let panel { Button("关闭") { panel.orderOut(nil) }.keyboardShortcut(.cancelAction) }
      }
      if !model.message.isEmpty { Text(model.message).font(.caption).textSelection(.enabled) }
    }.padding().background(.background, in: RoundedRectangle(cornerRadius: 14))
      .alert("清空所有剪贴板记录？", isPresented: $confirmingClear) {
        Button("取消", role: .cancel) {}
        Button("清空", role: .destructive) { Task { await model.clearHistory() } }
      } message: {
        Text("所有历史记录（含收藏）都将删除，无法撤销。")
      }
      .sheet(item: $preview) { ClipPreview(item: $0, store: model.store) }
      .onAppear {
        model.refresh()
        selected = model.items.first?.id
      }
      .onDisappear { resetConfirmation() }
      .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification, object: panel)) { _ in
        if panel != nil { resetConfirmation() }
      }
      .onChange(of: model.query) { _ in
        model.limit = 100
        model.refresh()
      }
  }
  private var historyList: some View {
    ScrollViewReader { scroll in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(model.items) { item in
            historyRow(item).id(item.id)
            if item.id != model.items.last?.id { Divider().padding(.leading, 42) }
          }
        }.padding(.horizontal, 8)
      }
      .historyKeyboardFocus()
      .onMoveCommand { direction in
        guard direction == .up || direction == .down, !model.items.isEmpty else { return }
        let current = model.items.firstIndex { $0.id == selected } ?? 0
        let index = min(model.items.count - 1, max(0, current + (direction == .down ? 1 : -1)))
        let id = model.items[index].id
        selected = id
        scroll.scrollTo(id)
      }
    }
  }

  private func historyRow(_ item: HistoryItem) -> some View {
    Button {
      selected = item.id
      restore(item)
    } label: {
      HStack(spacing: 8) {
        if item.kind == "image" {
          ClipThumbnail(item: item, store: model.store)
        } else {
          Image(systemName: "text.alignleft").frame(width: 28, height: 28)
        }
        Text(item.preview).lineLimit(2)
        Spacer()
        if item.pinned { Image(systemName: "star.fill").foregroundStyle(.orange) }
      }
      .padding(.horizontal, 6).frame(height: 36)
      .background(
        selected == item.id ? Color.primary.opacity(0.10) : .clear,
        in: RoundedRectangle(cornerRadius: 7))
      .contentShape(Rectangle())
    }
    .buttonStyle(HistoryRowStyle())
    .accessibilityAddTraits(selected == item.id ? .isSelected : [])
    .onContinuousHover { phase in
      guard case .active = phase else { return }
      let pointer = NSEvent.mouseLocation
      guard pointer != lastPointer else { return }
      lastPointer = pointer
      selected = item.id
    }
    .contextMenu {
      Button("预览") { preview = item }
      Button("复制") { restore(item) }
      Button(item.pinned ? "取消收藏" : "收藏") { modify(item, pin: true) }
      Button("删除", role: .destructive) { modify(item, pin: false) }
    }
  }

  private func resetConfirmation() {
    copyTask?.cancel()
    copyTask = nil
    confirmationVisible = false
  }

  func restore(_ item: HistoryItem) {
    resetConfirmation()
    copyTask = Task {
      guard await model.copy(item), !Task.isCancelled else { return }
      confirmationVisible = true
      NSAccessibility.post(
        element: NSApp as Any, notification: .announcementRequested,
        userInfo: [.announcement: "已复制", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
      do { try await Task.sleep(for: .seconds(1.2)) } catch { return }
      confirmationVisible = false
      panel?.orderOut(nil)
    }
  }
  func modify(_ item: HistoryItem, pin: Bool) {
    Task {
      do {
        if pin { try await model.store.pin(item.id) } else { try await model.store.remove(item.id) }
        model.refresh()
      } catch { model.message = error.localizedDescription }
    }
  }
}

private struct ClipPreview: View {
  let item: HistoryItem, store: History
  @Environment(\.dismiss) var dismiss
  var body: some View {
    VStack(alignment: .leading) {
      HStack {
        Text("记录预览").font(.headline)
        Spacer()
        Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      ClipContent(item: item, store: store).id(item.id)
    }.padding(20).frame(width: 500, height: 340)
  }
}

private struct ClipContent: View {
  let item: HistoryItem, store: History
  @ViewState private var image: CGImage?
  @ViewState private var text: String?
  @ViewState private var issue: String?

  var body: some View {
    Group {
      if let image {
        Image(decorative: image, scale: 1).resizable().scaledToFit().accessibilityLabel("剪贴板图片")
      } else if let text {
        ScrollView {
          Text(verbatim: text).textSelection(.enabled).frame(
            maxWidth: .infinity, alignment: .leading)
        }
      } else if let issue {
        Text(issue).foregroundStyle(.secondary)
      } else {
        ProgressView().controlSize(.small)
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .task {
        do {
          if item.kind == "image" {
            let loaded = try await store.imagePreview(item.id, maxPixels: 1400)
            try Task.checkCancellation()
            image = loaded
            if loaded == nil { issue = "无法显示图片" }
          } else {
            let data = try await store.payload(item.id)
            try Task.checkCancellation()
            text = data.map { String(decoding: $0, as: UTF8.self) }
            if data == nil { issue = "记录已删除" }
          }
        } catch { if !Task.isCancelled { issue = error.localizedDescription } }
      }
  }
}

private struct ClipThumbnail: View {
  let item: HistoryItem, store: History
  @ViewState private var image: CGImage?

  var body: some View {
    Group {
      if let image {
        Image(decorative: image, scale: 1).resizable().scaledToFit()
      } else {
        Image(systemName: "photo")
      }
    }.frame(width: 28, height: 28).accessibilityHidden(true)
      .task {
        let loaded = try? await store.imagePreview(item.id, maxPixels: 64)
        if !Task.isCancelled { image = loaded }
      }
  }
}

private struct ClipLimitField: View {
  let label: String, unit: String
  @Binding var value: Int
  let limits: ClosedRange<Int>
  @ViewState private var draft: String = ""
  @FocusState private var editing: Bool

  private func save() {
    if let number = Int(draft.trimmingCharacters(in: .whitespacesAndNewlines)) {
      value = min(limits.upperBound, max(limits.lowerBound, number))
    }
    draft = String(value)
  }

  var body: some View {
    HStack(spacing: 4) {
      Text(label)
      TextField(label, text: $draft).labelsHidden().textFieldStyle(.roundedBorder)
        .monospacedDigit().multilineTextAlignment(.trailing).frame(width: CGFloat(String(limits.upperBound).count * 9 + 10))
        .focused($editing).onSubmit {
          save()
          editing = false
        }
        .help("\(limits.lowerBound)–\(limits.upperBound) \(unit)")
      Text(unit)
    }
    .onAppear { draft = String(value) }
    .onChange(of: editing) { if !$0 { save() } }
    .onChange(of: value) { if !editing { draft = String($0) } }
    .onDisappear { if editing { save() } }
  }
}
