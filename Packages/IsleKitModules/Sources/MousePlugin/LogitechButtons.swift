import CHID
import Foundation

// One serial queue owns the HID handles, from discovery through releasing temporary diversion.
final class LogitechButtons: @unchecked Sendable {
  enum Event: Sendable {
    case status(String)
    case button(Int, Bool)
  }
  private let queue = DispatchQueue(label: "IsleKit.Logitech.buttons", qos: .userInitiated)
  private var timer: DispatchSourceTimer?
  private var handle: OpaquePointer?
  private var index: UInt8 = 0, feature: UInt8 = 0
  private var listening: Set<UInt16> = [], claimed: Set<UInt16> = [], held: Set<UInt16> = []
  private var retry = Date.distantPast
  static let numbers: [UInt16: Int] = [0x00c3: 6, 0x00c4: 7, 0x00d7: 8]

  static func pressed(_ report: [UInt8], index: UInt8, feature: UInt8) -> Set<UInt16>? {
    guard report.count >= 12, report.starts(with: [0x11, index, feature, 0]) else { return nil }
    return Set(
      stride(from: 4, to: 12, by: 2).map { UInt16(report[$0]) << 8 | UInt16(report[$0 + 1]) }.filter
      { $0 != 0 })
  }

  func configure(_ wanted: Set<Int>, report: @escaping @Sendable (Event) -> Void) {
    queue.async { [self] in
      self.stop()
      guard !wanted.isEmpty else { return }
      self.retry = .distantPast
      let timer = DispatchSource.makeTimerSource(queue: self.queue)
      timer.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(3))
      timer.setEventHandler { [weak self] in
        autoreleasepool { self?.poll(wanted, report: report) }
      }
      self.timer = timer
      timer.resume()
    }
  }

  func shutdown() { queue.sync { stop() } }

  private func stop() {
    timer?.cancel()
    timer = nil
    releaseDevice()
  }

  private func releaseDevice() {
    guard let handle else { return }
    for cid in claimed {
      _ = try? Logitech.request(
        handle, index: index, feature: feature, function: 3,
        params: [UInt8(cid >> 8), UInt8(truncatingIfNeeded: cid), 2, 0, 0], softwareID: 13)
    }
    hid_close(handle)
    self.handle = nil
    listening.removeAll()
    held.removeAll()
    claimed.removeAll()
  }

  private func poll(_ wanted: Set<Int>, report: @escaping @Sendable (Event) -> Void) {
    if handle == nil {
      guard Date() >= retry else { return }
      retry = Date().addingTimeInterval(8)
      guard discover(wanted) else {
        report(.status("正在等待支持额外按键的罗技设备。"))
        return
      }
      report(.status(""))
    }
    guard let handle else { return }
    var buffer = [UInt8](repeating: 0, count: 64)
    for _ in 0..<64 {
      let count = hid_read_timeout(handle, &buffer, buffer.count, 0)
      if count == 0 { break }
      if count < 0 {
        releaseDevice()
        report(.status("罗技设备已断开，正在重新连接。"))
        return
      }
      guard
        let current = Self.pressed(Array(buffer.prefix(Int(count))), index: index, feature: feature)
      else { continue }
      let next = current.intersection(listening)
      for cid in held.subtracting(next) {
        if let n = Self.numbers[cid] { report(.button(n, false)) }
      }
      for cid in next.subtracting(held) {
        if let n = Self.numbers[cid] { report(.button(n, true)) }
      }
      held = next
    }
  }

  private func discover(_ wanted: Set<Int>) -> Bool {
    for endpoint in Logitech.endpoints() {
      for slot: UInt8 in endpoint.bluetooth ? [255] : [1, 2, 3, 4, 5, 6, 255] {
        guard let candidate = Logitech.open(endpoint.path) else { break }
        handle = candidate
        index = slot
        do {
          feature = try Logitech.request(
            candidate, index: slot, feature: 0, function: 0,
            params: [0x1b, 0x04, 0], softwareID: 13)[0]
          if feature != 0 {
            let count = min(32, try control(0, [])[0])
            for offset in 0..<count {
              let info = try control(1, [offset])
              guard info.count >= 5, info[4] & 0x20 != 0 else { continue }
              let cid = UInt16(info[0]) << 8 | UInt16(info[1])
              guard let number = Self.numbers[cid], wanted.contains(number) else { continue }
              let id = Array(info.prefix(2))
              let before = try control(2, id)
              guard before.count >= 3, before.starts(with: id) else { continue }
              // Subscribe to existing diversion too. Only undo diversion enabled by this session.
              if before[2] & 1 != 0 {
                listening.insert(cid)
                continue
              }
              claimed.insert(cid)
              _ = try control(3, id + [3, 0, 0])
              let after = try control(2, id)
              guard after.count >= 3, after.starts(with: id), after[2] & 1 == 1 else {
                throw HIDError("设备没有应用按键映射")
              }
              listening.insert(cid)
            }
            if !listening.isEmpty { return true }
          }
        } catch { /* Probe the next receiver slot after releasing any partial claim. */  }
        releaseDevice()
      }
    }
    return false
  }

  private func control(_ function: UInt8, _ params: [UInt8]) throws -> [UInt8] {
    guard let handle else { throw HIDError("设备已断开") }
    return try Logitech.request(
      handle, index: index, feature: feature, function: function, params: params, softwareID: 13)
  }
}
