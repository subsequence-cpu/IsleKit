import DesignSystem
import PluginKit
import SwiftUI

@MainActor public final class DeveloperTools: IslandPlugin {
  public init() {}
  public let id = "developer-tools", title = "开发工具", icon = "terminal",
    summary = "12 项离线工具，涵盖编解码、文本、时间与哈希。"
  public var commands: [ToolCommand] {
    Utility.allCases.map { ToolCommand(id + "." + $0.rawValue, $0.title, $0.icon, title) }
  }
  private var sessions: [Utility: ToolSession] = [:]
  public func setEnabled(_ enabled: Bool) {
    if !enabled { sessions.removeAll() }
  }
  public func page(command: String?) -> AnyView {
    let tool =
      command?.split(separator: ".").last.flatMap { Utility(rawValue: String($0)) } ?? .json
    let session = sessions[tool] ?? ToolSession(tool)
    sessions[tool] = session
    return AnyView(Workbench(tool: tool, session: session).id(tool))
  }
}

@MainActor final class ToolSession: ObservableObject {
  private let tool: Utility
  private let defaults: UserDefaults
  @Published var operation: String {
    didSet { defaults.set(operation, forKey: "developer-tools.\(tool.rawValue).operation") }
  }
  @Published var input: String
  @Published var extra = "" {
    didSet {
      guard tool == .uuid else { return }
      if extra.isEmpty {
        defaults.removeObject(forKey: "developer-tools.uuid.length")
      } else if let count = Int(extra), (1...4096).contains(count) {
        defaults.set(count, forKey: "developer-tools.uuid.length")
      }
    }
  }
  @Published var replacement = ""
  @Published var result = ""
  @Published var error = ""
  @Published var indent: Int {
    didSet { defaults.set(indent, forKey: "developer-tools.json.indent") }
  }
  init(_ tool: Utility, defaults: UserDefaults = .standard) {
    self.tool = tool
    self.defaults = defaults
    let saved = defaults.string(forKey: "developer-tools.\(tool.rawValue).operation")
    operation = tool.operations.first { $0 == saved } ?? tool.operations[0]
    indent = defaults.integer(forKey: "developer-tools.json.indent") == 4 ? 4 : 2
    let length = defaults.integer(forKey: "developer-tools.uuid.length")
    if tool == .uuid, (1...4096).contains(length) { extra = String(length) }
    input = tool.sample
  }
}

private struct Workbench: View {
  let tool: Utility
  @ObservedObject var session: ToolSession
  @ViewState private var task: Task<Void, Never>?
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        if tool.operations.count > 1 {
          Picker("操作", selection: $session.operation) {
            ForEach(tool.operations, id: \.self) { Text($0) }
          }.labelsHidden().fixedSize()
        }
        if tool == .json && session.operation == "格式化" {
          Picker("缩进", selection: $session.indent) {
            Text("2 个空格").tag(2)
            Text("4 个空格").tag(4)
          }.labelsHidden().fixedSize()
        }
        Spacer()
        Button(task == nil ? session.operation : "处理中…", action: run).buttonStyle(
          .borderedProminent
        )
        .keyboardShortcut(.return, modifiers: .command).disabled(task != nil)
      }
      if tool == .regex {
        TextField("正则表达式", text: $session.extra)
        if session.operation == "替换" { TextField("替换模板（支持 $1）", text: $session.replacement) }
      } else if tool == .hash && session.operation.hasPrefix("HMAC") {
        SecureField("HMAC 密钥", text: $session.extra)
      } else if tool == .uuid && session.operation == "随机字符串" {
        TextField("长度（默认 32）", text: $session.extra)
      }
      HSplitView {
        VStack(alignment: .leading) {
          Text(tool == .diff ? "原文" : "输入").font(.headline)
          SourceEditor(content: $session.input)
          if tool == .diff {
            Text("对比文本").font(.headline)
            SourceEditor(content: $session.extra)
          }
        }.padding().frame(minWidth: 200).background(white)
        VStack(alignment: .leading) {
          HStack {
            Text("结果").font(.headline)
            Spacer()
            Button("复制") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(session.result, forType: .string)
            }
            .disabled(session.result.isEmpty)
          }
          ScrollView([.horizontal, .vertical]) {
            Text(verbatim: session.result).font(.system(.body, design: .monospaced)).textSelection(
              .enabled
            ).padding(6)
          }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.padding().frame(minWidth: 200).foregroundStyle(white).background(ink(0x283E3B))
      }.clipShape(RoundedRectangle(cornerRadius: 14))
      if !session.error.isEmpty {
        Text(session.error).foregroundStyle(.red).textSelection(.enabled)
      }
    }.textFieldStyle(.roundedBorder).onDisappear {
      task?.cancel()
      task = nil
    }
  }
  func run() {
    let tool = tool
    let input = session.input
    let op = session.operation
    let arg = session.extra
    let replacement = session.replacement
    let indent = session.indent
    session.error = ""
    task = Task {
      let answer = await Task.detached(priority: .userInitiated) {
        Result {
          try tool.run(input, operation: op, extra: arg, replacement: replacement, indent: indent)
        }
      }.value
      guard !Task.isCancelled else { return }
      switch answer {
      case .success(let value): session.result = value
      case .failure(let failure):
        session.error = failure.localizedDescription
        session.result = ""
      }
      task = nil
    }
  }
}

private struct SourceEditor: NSViewRepresentable {
  @Binding var content: String
  final class Coordinator: NSObject, NSTextViewDelegate {
    var content: Binding<String>
    init(_ content: Binding<String>) { self.content = content }
    func textDidChange(_ notification: Notification) {
      if let editor = notification.object as? NSTextView { content.wrappedValue = editor.string }
    }
  }
  func makeCoordinator() -> Coordinator { Coordinator($content) }
  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSTextView.scrollableTextView()
    let view = scroll.documentView as! NSTextView
    view.delegate = context.coordinator
    view.isRichText = false
    view.allowsUndo = true
    view.isAutomaticQuoteSubstitutionEnabled = false
    view.isAutomaticDashSubstitutionEnabled = false
    view.isAutomaticTextReplacementEnabled = false
    view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    view.drawsBackground = false
    scroll.drawsBackground = false
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let view = scroll.documentView as? NSTextView, view.string != content else { return }
    view.string = content
  }
}
