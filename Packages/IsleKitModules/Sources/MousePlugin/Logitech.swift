import CHID
import Foundation

struct Sensor: Identifiable, Sendable {
  let path: String, index: UInt8, number: UInt8, name: String, current: Int, values: [Int]
  var id: String { "\(path):\(index):\(number)" }
}

struct HIDError: LocalizedError {
  var errorDescription: String?
  init(_ text: String) { errorDescription = text }
}

actor Logitech {

  struct Endpoint: Sendable {
    let path: String, productName: String?, bluetooth: Bool
  }

  // hidapi initialization, error strings, and open options are process-wide.
  private static let discoveryLock = NSLock()

  static func endpoints() -> [Endpoint] {
    discoveryLock.withLock {
      let head = hid_enumerate(0x046d, 0)
      defer { hid_free_enumeration(head) }
      var result: [Endpoint] = []
      var node = head
      while let current = node {
        let info = current.pointee
        node = info.next
        let bluetooth =
          info.bus_type == HID_API_BUS_BLUETOOTH && info.usage_page == 1 && info.usage == 2
        let usb = info.bus_type == HID_API_BUS_USB && info.usage_page >= 0xff00 && info.usage == 1
        guard bluetooth || usb, let ptr = info.path else { continue }
        let path = String(cString: ptr)
        if !result.contains(where: { $0.path == path }) {
          let productName = info.product_string.map { pointer in
            let scalars = UnsafeBufferPointer(start: pointer, count: wcslen(pointer)).map {
              UInt32(bitPattern: $0)
            }
            return String(decoding: scalars, as: UTF32.self)
          }
          result.append(Endpoint(path: path, productName: productName, bluetooth: bluetooth))
        }
      }
      return result
    }
  }

  static func open(_ path: String) -> OpaquePointer? {
    discoveryLock.withLock {
      guard hid_init() == 0 else { return nil }
      hid_darwin_set_open_exclusive(0)
      return hid_open_path(path)
    }
  }

  static func request(
    _ handle: OpaquePointer, index: UInt8, feature: UInt8, function: UInt8, params: [UInt8],
    softwareID: UInt8 = 1
  ) throws -> [UInt8] {
    try Task.checkCancellation()
    var packet = [UInt8](repeating: 0, count: 20)
    packet.replaceSubrange(0..<4, with: [0x11, index, feature, function << 4 | softwareID])
    packet.replaceSubrange(4..<(4 + params.count), with: params)
    guard hid_write(handle, packet, packet.count) == packet.count else {
      throw HIDError("HID++ 发送失败")
    }
    let deadline = ContinuousClock.now + .milliseconds(260)
    var reply = [UInt8](repeating: 0, count: 64)
    while ContinuousClock.now < deadline {
      try Task.checkCancellation()
      let n = Int(hid_read_timeout(handle, &reply, reply.count, 20))
      guard n >= 0 else { throw HIDError("设备已断开") }
      if n >= 7, reply[1] == index, reply[2] == 0xff, reply[3] == feature, reply[4] == packet[3] {
        throw HIDError("设备拒绝请求（\(reply[5])）")
      }
      if n >= 7, [0x10, 0x11].contains(reply[0]), reply[1...3] == packet[1...3] {
        return Array(reply[4..<n])
      }
    }
    throw HIDError("设备没有回应 HID++ 请求")
  }

  static func modelName(
    _ handle: OpaquePointer, index: UInt8, endpoint: Endpoint, softwareID: UInt8 = 1
  ) -> String {
    // A receiver's USB product string names the adapter. Read the paired mouse's name per slot.
    do {
      let feature = try request(
        handle, index: index, feature: 0, function: 0, params: [0, 5, 0], softwareID: softwareID)[0]
      if feature != 0 {
        let length = Int(
          try request(
            handle, index: index, feature: feature, function: 0, params: [], softwareID: softwareID)[
              0])
        var bytes: [UInt8] = []
        while bytes.count < length {
          let part = try request(
            handle, index: index, feature: feature, function: 1, params: [UInt8(bytes.count)],
            softwareID: softwareID)
          bytes += part.prefix(length - bytes.count)
        }
        if let name = String(bytes: bytes, encoding: .utf8)?.trimmingCharacters(
          in: .whitespacesAndNewlines), !name.isEmpty
        {
          return name
        }
      }
    } catch { /* Some devices only expose their Bluetooth product name. */  }
    if endpoint.bluetooth, let name = endpoint.productName, !name.isEmpty { return name }
    return endpoint.bluetooth ? "罗技蓝牙鼠标" : "罗技接收器 · 通道 \(index)"
  }

  private func sensors(handle: OpaquePointer, path: String, index: UInt8, name: () -> String) throws
    -> (
      UInt8, [Sensor]
    )
  {
    let feature = try Self.request(
      handle, index: index, feature: 0, function: 0, params: [0x22, 0x01, 0])[0]
    guard feature != 0 else { throw HIDError("此设备不支持 HID++ DPI") }
    let count = try Self.request(handle, index: index, feature: feature, function: 0, params: [])[0]
    guard (1...8).contains(count) else { throw HIDError("传感器数量无效") }
    let model = name()
    var sensors: [Sensor] = []
    for number in 0..<count {
      let data = try Self.request(
        handle, index: index, feature: feature, function: 1, params: [number])
      guard data.first == number else { throw HIDError("传感器响应不一致") }
      var values: [Int] = []
      var pos = 1
      while pos + 1 < data.count {
        let word = Int(data[pos]) << 8 | Int(data[pos + 1])
        pos += 2
        if word == 0 { break }
        if word & 0xe000 == 0xe000 {
          let step = word & 0x1fff
          guard let start = values.last, pos + 1 < data.count, step > 0 else {
            throw HIDError("DPI 范围无效")
          }
          let end = Int(data[pos]) << 8 | Int(data[pos + 1])
          pos += 2
          guard end > start, end < 0xe000, (end - start) / step <= 4096 else {
            throw HIDError("DPI 范围无效")
          }
          values += stride(from: start + step, through: end, by: step)
        } else {
          values.append(word)
        }
      }
      let dpi = try readDPI(handle, index: index, feature: feature, number: number)
      guard values.contains(dpi) else { throw HIDError("当前 DPI 不在支持范围内") }
      sensors.append(
        Sensor(path: path, index: index, number: number, name: model, current: dpi, values: values))
    }
    return (feature, sensors)
  }

  func scan() throws -> [Sensor] {
    var result: [Sensor] = []
    for endpoint in Self.endpoints() {
      try Task.checkCancellation()
      guard let handle = Self.open(endpoint.path) else { continue }
      defer { hid_close(handle) }
      for index: UInt8 in endpoint.bluetooth ? [255] : [255, 1, 2, 3, 4, 5, 6] {
        try Task.checkCancellation()
        if let found = try? sensors(
          handle: handle, path: endpoint.path, index: index,
          name: { Self.modelName(handle, index: index, endpoint: endpoint) })
        {
          result += found.1
        }
      }
    }
    return result
  }
  private func readDPI(_ handle: OpaquePointer, index: UInt8, feature: UInt8, number: UInt8) throws
    -> Int
  {
    let data = try Self.request(
      handle, index: index, feature: feature, function: 2, params: [number])
    guard data.count >= 5, data[0] == number else { throw HIDError("无法读取当前 DPI") }
    let value = Int(data[1]) << 8 | Int(data[2])
    return value == 0 ? Int(data[3]) << 8 | Int(data[4]) : value
  }

  func set(_ value: Int, sensor: Sensor) throws -> Sensor {
    guard sensor.values.contains(value) else { throw HIDError("设备不支持该 DPI") }
    guard let handle = Self.open(sensor.path) else { throw HIDError("设备已断开") }
    defer { hid_close(handle) }
    let feature = try Self.request(
      handle, index: sensor.index, feature: 0, function: 0, params: [0x22, 0x01, 0])[0]
    guard feature != 0 else { throw HIDError("此设备不支持 HID++ DPI") }
    _ = try Self.request(
      handle, index: sensor.index, feature: feature, function: 3,
      params: [sensor.number, UInt8(value >> 8), UInt8(value & 255)])
    let applied = try readDPI(handle, index: sensor.index, feature: feature, number: sensor.number)
    guard applied == value else { throw HIDError("设备未应用该 DPI，请重新扫描") }
    return Sensor(
      path: sensor.path, index: sensor.index, number: sensor.number, name: sensor.name,
      current: applied, values: sensor.values)
  }
}
