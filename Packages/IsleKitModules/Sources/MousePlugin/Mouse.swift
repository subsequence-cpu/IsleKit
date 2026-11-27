@preconcurrency import ApplicationServices
import OSLog
import PluginKit
import SwiftUI

enum ButtonCaptureState: Equatable {
  case idle, listening
  case identified(Int)
  case timedOut
}

@MainActor public final class Mouse: ObservableObject, IslandPlugin {
  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    preferences = MousePreferences.load(defaults)
    let buttons = hardware
    quitObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification,
      object: nil, queue: .main
    ) { _ in buttons.shutdown() }
  }
  private var quitObserver: NSObjectProtocol?
  private let hardware = LogitechButtons()
  private var requestedButtons: Set<Int> = []
  private var hardwareGeneration = 0
  private var hardwarePresses: [Int: MousePress] = [:]
  private var hardwareOffset = CGPoint.zero
  private var permissionTask: Task<Void, Never>?
  public let id = "mouse", title = "鼠标增强", icon = "mouse", summary = "配置按键绑定、滚轮手感与罗技硬件 DPI。"
  private let defaults: UserDefaults
  private let hid = Logitech()
  private var tap: CFMachPort?, source: CFRunLoopSource?
  private var presses: [Int: MousePress] = [:]
  private var captureTask: Task<Void, Never>?, scanTask: Task<Void, Never>?
  private var dpiTask: Task<Void, Never>?
  @Published private(set) var requestedDPI: [String: Int] = [:]
  private let wheel = MouseWheel()
  @Published var preferences: MousePreferences {
    didSet {
      defaults.set(try? JSONEncoder().encode(preferences), forKey: "mouse.preferences")
      updateHardware()
    }
  }
  @Published private(set) var enabled = false
  @Published private(set) var connected = false
  @Published private(set) var captureState: ButtonCaptureState = .idle
  var capturing: Bool { captureState == .listening }
  private let log = Logger(subsystem: "io.github.subsequence-cpu.IsleKit", category: "Mouse")
  @Published var status = "" { didSet { log.info("\(self.status, privacy: .public)") } }
  @Published var buttonStatus = "" {
    didSet { if oldValue != buttonStatus { log.info("\(self.buttonStatus, privacy: .public)") } }
  }
  @Published private(set) var scanNeedsPermission = false
  @Published var dpiStatus = ""
  @Published var needsInputPermission = false
  @Published var sensors: [Sensor] = []
  @Published var busy = false
  public func setEnabled(_ enabled: Bool) {
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    if let tap { CFMachPortInvalidate(tap) }
    source = nil
    tap = nil
    permissionTask?.cancel()
    self.enabled = enabled
    connected = false
    presses.removeAll()
    cancelCapture()
    wheel.stop()
    dpiStatus = ""
    scanNeedsPermission = false
    scanTask?.cancel()
    dpiTask?.cancel()
    dpiTask = nil
    requestedDPI.removeAll()
    busy = false
    guard enabled else {
      status = "启用后，按键绑定与滚轮配置会生效。"
      sensors = []
      return
    }
    guard AXIsProcessTrusted() else {
      status = "等待辅助功能授权，按键与滚轮尚未接管。"
      permissionTask = Task { [weak self] in
        while !Task.isCancelled {
          do { try await Task.sleep(for: .seconds(2)) } catch { return }
          if AXIsProcessTrusted() {
            self?.setEnabled(true)
            return
          }
        }
      }
      return
    }
    let types: [CGEventType] = [
      .scrollWheel, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .mouseMoved,
    ]
    let mask = types.reduce(UInt64(0)) { $0 | 1 << $1.rawValue }
    tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
      eventsOfInterest: mask,
      callback: { _, type, event, ref in
        guard let ref else { return Unmanaged.passUnretained(event) }
        let owner = Unmanaged<Mouse>.fromOpaque(ref).takeUnretainedValue()
        let keep = MainActor.assumeIsolated { owner.process(type, event) }
        return keep ? Unmanaged.passUnretained(event) : nil
      }, userInfo: Unmanaged.passUnretained(self).toOpaque())
    guard let tap else {
      status = "无法连接鼠标事件，请检查辅助功能权限。"
      return
    }
    source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    connected = true
    status = "鼠标事件已连接"
    updateHardware()
  }

  func openAccessibility() {
    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    openPrivacy("Accessibility")
  }

  func openInputMonitoring() {
    _ = CGRequestListenEventAccess()
    openPrivacy("ListenEvent")
  }

  private func openPrivacy(_ pane: String) {
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + pane)
    {
      NSWorkspace.shared.open(url)
    }
  }

  func refreshPermissions() {
    if enabled && !connected && AXIsProcessTrusted() { setEnabled(true) } else { updateHardware() }
  }

  private func updateHardware() {
    let bound = Set(
      LogitechButtons.numbers.values.filter { capturing || preferences[$0] != .system })
    needsInputPermission = connected && !bound.isEmpty && !CGPreflightListenEventAccess()
    let wanted = connected && !needsInputPermission ? bound : []
    if needsInputPermission {
      buttonStatus = "罗技额外按键等待输入监控授权。"
    } else if wanted.isEmpty {
      buttonStatus = ""
    }
    guard requestedButtons != wanted else { return }
    requestedButtons = wanted
    hardwareGeneration += 1
    let generation = hardwareGeneration
    hardwarePresses.removeAll()
    if !wanted.isEmpty { buttonStatus = "正在连接罗技额外按键…" }
    hardware.configure(wanted) { [weak self] event in
      DispatchQueue.main.async {
        guard let self, self.hardwareGeneration == generation else { return }
        switch event {
        case .status(let message):
          self.hardwarePresses.removeAll()
          self.buttonStatus = message
        case .button(let number, let down):
          if down {
            if self.capturing {
              self.identify(number)
            } else if self.preferences[number] != .system {
              if self.hardwarePresses.isEmpty { self.hardwareOffset = .zero }
              self.hardwarePresses[number] = MousePress(
                action: self.preferences[number], start: self.hardwareOffset)
            }
          } else if var press = self.hardwarePresses.removeValue(forKey: number) {
            self.post(press.key(at: self.hardwareOffset, released: true), button: number)
          }
        }
      }
    }
  }

  func startCapture() {
    guard connected else { return }
    cancelCapture()
    captureState = .listening
    updateHardware()
    captureTask = Task {
      do { try await Task.sleep(for: .seconds(15)) } catch { return }
      cancelCapture()
      captureState = .timedOut
    }
  }

  private func identify(_ number: Int) {
    preferences[number] = preferences[number]
    cancelCapture()
    captureState = .identified(number)
  }

  func cancelCapture() {
    captureTask?.cancel()
    captureTask = nil
    captureState = .idle
    updateHardware()
  }

  private func process(_ type: CGEventType, _ event: CGEvent) -> Bool {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      presses.removeAll()
      wheel.stop()
      cancelCapture()
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return true
    }
    if type == .mouseMoved {
      guard
        hardwarePresses.values.contains(where: {
          $0.action == .spaces || $0.action == .navigationGesture
        })
      else { return true }
      hardwareOffset.x += CGFloat(event.getIntegerValueField(.mouseEventDeltaX))
      hardwareOffset.y += CGFloat(event.getIntegerValueField(.mouseEventDeltaY))
      for number in Array(hardwarePresses.keys) {
        let key = hardwarePresses[number]?.key(at: hardwareOffset, released: false)
        post(key, button: number)
      }
      return false
    }
    if type == .scrollWheel { return wheel.handle(event, preferences: preferences) }
    let button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
    guard (3...32).contains(button) else { return true }
    if type == .otherMouseDown {
      var action = preferences[button]
      if capturing {
        identify(button)
        action = .disabled
      }
      guard action != .system else { return true }
      presses[button] = MousePress(action: action, start: event.location)
      return false
    }
    guard var press = presses[button] else { return true }
    let released = type == .otherMouseUp
    post(press.key(at: event.location, released: released), button: button)
    presses[button] = released ? nil : press
    return false
  }

  private func post(_ mapping: (CGKeyCode, CGEventFlags)?, button: Int) {
    guard let (key, flags) = mapping else { return }
    let source = CGEventSource(stateID: .combinedSessionState)
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
    else { return }
    for event in [down, up] {
      event.flags = Self.keyFlags(key, flags)
      event.post(tap: .cgSessionEventTap)
    }
    if flags == .maskControl,
      let gesture = [123: "上一个桌面", 124: "下一个桌面", 125: "应用窗口", 126: "调度中心"][Int(key)]
    {
      log.debug("按键 \(button) 已触发：\(gesture, privacy: .public)")
    }
  }

  static func keyFlags(_ key: CGKeyCode, _ modifiers: CGEventFlags) -> CGEventFlags {
    (123...126).contains(key) ? modifiers.union([.maskNumericPad, .maskSecondaryFn]) : modifiers
  }

  func scanOnEntry() async {
    guard enabled else { return }
    await dpiTask?.value
    guard !Task.isCancelled else { return }
    scanDevices(requestPermission: false)
  }

  func scanDevices(requestPermission: Bool) {
    guard enabled, !busy, requestedDPI.isEmpty else { return }
    guard CGPreflightListenEventAccess() else {
      scanNeedsPermission = true
      if requestPermission { openInputMonitoring() }
      dpiStatus = "允许输入监控后即可读取鼠标 DPI。"
      return
    }
    scanNeedsPermission = false
    dpiStatus = ""
    busy = true
    scanTask = Task {
      do {
        let found = try await hid.scan()
        try Task.checkCancellation()
        sensors = found
        dpiStatus = sensors.isEmpty ? "未发现支持 HID++ DPI 的罗技设备" : ""
      } catch { if !Task.isCancelled { dpiStatus = error.localizedDescription } }
      if !Task.isCancelled { busy = false }
    }
  }

  func setDPI(_ value: Int, for sensor: Sensor) {
    guard enabled, !busy, sensor.values.contains(value),
      (requestedDPI[sensor.id] ?? sensor.current) != value
    else { return }
    requestedDPI[sensor.id] = value
    guard dpiTask == nil else { return }
    dpiTask = Task {
      // While a hardware write is in flight, keep only the newest slider position per sensor.
      while !Task.isCancelled, let target = sensors.first(where: { requestedDPI[$0.id] != nil }),
        let next = requestedDPI[target.id]
      {
        do {
          let updated = try await hid.set(next, sensor: target)
          try Task.checkCancellation()
          if let index = sensors.firstIndex(where: { $0.id == updated.id }) {
            sensors[index] = updated
          }
          dpiStatus = ""
        } catch {
          guard !Task.isCancelled else { return }
          dpiStatus = error.localizedDescription
        }
        if requestedDPI[target.id] == next { requestedDPI[target.id] = nil }
      }
      if !Task.isCancelled { dpiTask = nil }
    }
  }

  public func page(command: String?) -> AnyView { AnyView(MousePage(model: self)) }
}
