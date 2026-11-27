import ApplicationServices
import Foundation

struct MousePress {
  let action: ButtonAction
  let start: CGPoint
  private var dragged = false, triggered = false

  init(action: ButtonAction, start: CGPoint) {
    self.action = action
    self.start = start
  }

  mutating func key(at point: CGPoint, released: Bool) -> (CGKeyCode, CGEventFlags)? {
    let dx = point.x - start.x
    let dy = point.y - start.y
    let x = abs(dx)
    let y = abs(dy)
    dragged = dragged || hypot(x, y) > 12
    if action == .spaces {
      guard !triggered else { return nil }
      let code: CGKeyCode
      if x >= 96 && x >= y * 1.8 {
        code = dx < 0 ? 124 : 123
      } else if y >= 120 && y >= x * 1.8 {
        code = dy < 0 ? 126 : 125
      } else if released && !dragged {
        code = 126
      } else {
        return nil
      }
      triggered = true
      return (code, .maskControl)
    }
    guard released else { return nil }
    switch action {
    case .back: return (33, .maskCommand)
    case .forward: return (30, .maskCommand)
    case .desktop: return (103, [])
    case .quickLook: return (49, [])
    case .navigationGesture where max(x, y) >= 24:
      return (x >= y ? (dx > 0 ? 30 : 33) : (dy > 0 ? 125 : 126), .maskCommand)
    default: return nil
    }
  }
}

@MainActor final class MouseWheel {
  private var task: Task<Void, Never>?
  private var vertical = 0, horizontal = 0
  private var flags: CGEventFlags = []

  func stop() {
    task?.cancel()
    task = nil
    vertical = 0
    horizontal = 0
  }

  func handle(_ event: CGEvent, preferences p: MousePreferences) -> Bool {
    guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0,
      event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0,
      event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty,
      p.smoothScrolling || p.reverseVertical || p.reverseHorizontal || p.scrollSpeed != 1
    else { return true }
    func pixels(_ points: CGEventField, _ lines: CGEventField, reverse: Bool) -> Int {
      let position = event.getIntegerValueField(points)
      let delta = position == 0 ? Double(event.getIntegerValueField(lines)) * 12 : Double(position)
      return Int((min(4096, max(-4096, delta)) * p.scrollSpeed * (reverse ? -1 : 1)).rounded())
    }
    let v = pixels(
      .scrollWheelEventPointDeltaAxis1, .scrollWheelEventDeltaAxis1, reverse: p.reverseVertical)
    let h = pixels(
      .scrollWheelEventPointDeltaAxis2, .scrollWheelEventDeltaAxis2, reverse: p.reverseHorizontal)
    guard v != 0 || h != 0 else { return true }
    if event.flags != flags { stop() }
    flags = event.flags
    if !p.smoothScrolling {
      stop()
      return !post(v, h)
    }
    func accumulate(_ pending: Int, _ step: Int) -> Int {
      if step == 0 { return pending }
      return min(16384, max(-16384, (pending.signum() == step.signum() ? pending : 0) + step))
    }
    let startV = accumulate(vertical, v)
    let startH = accumulate(horizontal, h)
    vertical = startV
    horizontal = startH
    task?.cancel()
    let start = ProcessInfo.processInfo.systemUptime
    task = Task {
      while !Task.isCancelled {
        let t = min(
          1, (ProcessInfo.processInfo.systemUptime - start) * 1000 / Double(p.smoothDurationMs))
        let fraction = pow(1 - t, 3)
        let nextV = Int((Double(startV) * fraction).rounded())
        let nextH = Int((Double(startH) * fraction).rounded())
        if nextV != vertical || nextH != horizontal {
          _ = post(vertical - nextV, horizontal - nextH)
        }
        vertical = nextV
        horizontal = nextH
        if nextV == 0 && nextH == 0 {
          task = nil
          return
        }
        do { try await Task.sleep(for: .milliseconds(8)) } catch { return }
      }
    }
    return false
  }

  private func post(_ v: Int, _ h: Int) -> Bool {
    guard
      let event = CGEvent(
        scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
        wheel1: Int32(v), wheel2: Int32(h), wheel3: 0)
    else { return false }
    event.flags = flags
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    event.post(tap: .cgSessionEventTap)
    return true
  }
}
