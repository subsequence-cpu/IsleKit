import DesignSystem
import PluginKit
import SwiftUI

private let sliderValueWidth: CGFloat = 80

struct MousePage: View {
  @ObservedObject var model: Mouse
  private func title(_ button: Int) -> String {
    switch button {
    case 3: "中键 · 3"
    case 4, 5: "侧键 · \(button)"
    default: "额外按键 · \(button)"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Label(model.status, systemImage: model.connected ? "checkmark.circle" : "info.circle")
        Spacer()
        if model.enabled && !model.connected {
          Button("辅助功能权限…") { model.openAccessibility() }
          Button("重新连接") { model.setEnabled(true) }
        }
      }
      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Label("罗技硬件 DPI", systemImage: "scope").font(.headline)
            Spacer()
            Button(model.scanNeedsPermission ? "授权扫描" : "重新扫描") {
              model.scanDevices(requestPermission: true)
            }.disabled(
              !model.enabled || model.busy || !model.requestedDPI.isEmpty)
            if model.busy { ProgressView().controlSize(.small) }
          }
          if !model.dpiStatus.isEmpty { Text(model.dpiStatus).font(.callout) }
          ForEach(model.sensors) { sensor in
            SensorControl(
              sensor: sensor, value: model.requestedDPI[sensor.id] ?? sensor.current,
              showSensorNumber: model.sensors.contains(where: {
                $0.path == sensor.path && $0.index == sensor.index && $0.number != sensor.number
              })
            ) { value in
              model.setDPI(value, for: sensor)
            }.disabled(!model.enabled || model.busy)
          }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
      }
      captureCard
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(model.preferences.buttons, id: \.self) { button in
            LabeledContent(title(button)) {
              Picker(
                title(button),
                selection: Binding(
                  get: { model.preferences[button] },
                  set: { model.preferences[button] = $0 })
              ) {
                ForEach(ButtonAction.allCases, id: \.self) { Text($0.title).tag($0) }
              }.labelsHidden().frame(width: 200)
            }
          }
          if !model.buttonStatus.isEmpty { Text(model.buttonStatus).font(.callout) }
          if model.needsInputPermission {
            Button("输入监控权限…") { model.openInputMonitoring() }
          }
        }.padding(8)
      } label: {
        Label("按键绑定", systemImage: "computermouse")
      }
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          LabeledContent("滚动速度") {
            Slider(value: $model.preferences.scrollSpeed, in: 0.25...4, step: 0.05)
              .frame(maxWidth: .infinity).accessibilityLabel("滚动速度")
            Text(String(format: "%.2f×", model.preferences.scrollSpeed)).monospacedDigit().frame(
              width: sliderValueWidth, alignment: .trailing)
          }
          Toggle("平滑滚动", isOn: $model.preferences.smoothScrolling)
          LabeledContent("平滑时长") {
            Slider(
              value: Binding(
                get: { Double(model.preferences.smoothDurationMs) },
                set: { model.preferences.smoothDurationMs = Int($0.rounded()) }), in: 80...400,
              step: 10
            )
            .frame(maxWidth: .infinity).accessibilityLabel("平滑时长")
            Text("\(model.preferences.smoothDurationMs) ms").monospacedDigit().frame(width: sliderValueWidth, alignment: .trailing)
          }.disabled(!model.preferences.smoothScrolling)
          Toggle("反转垂直滚动", isOn: $model.preferences.reverseVertical)
          Toggle("反转水平滚动", isOn: $model.preferences.reverseHorizontal)
        }.padding(8)
      } label: {
        Label("滚轮", systemImage: "arrow.up.and.down")
      }
    }
    .task(id: model.enabled) { await model.scanOnEntry() }
    .onDisappear { model.cancelCapture() }
    .onReceive(
      NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
    ) { _ in
      let waitingForScan = model.scanNeedsPermission
      model.refreshPermissions()
      if waitingForScan { model.scanDevices(requestPermission: false) }
    }
  }

  private var captureDetail: String? {
    switch model.captureState {
    case .idle:
      model.connected ? nil : "连接鼠标后可用"
    case .listening: "请在 15 秒内按下鼠标中键或侧键。"
    case .identified(let number): "已识别 · " + title(number) + "   " + model.preferences[number].title
    case .timedOut: "未检测到按键，可以再次识别。"
    }
  }

  private var captureCard: some View {
    HStack(spacing: 14) {
      ZStack {
        RoundedRectangle(cornerRadius: 12).fill(DesignSystem.paper)
        Artwork(name: "mouse", size: 32).accessibilityHidden(true)
      }.frame(width: 48, height: 48)
      VStack(alignment: .leading, spacing: 4) {
        Text("按键识别").font(.headline)
        if let captureDetail {
          Text(captureDetail).font(.callout).foregroundStyle(DesignSystem.quiet)
        }
      }
      Spacer(minLength: 8)
      if model.capturing { ProgressView().controlSize(.small) }
      Button(model.capturing ? "取消识别" : "开始识别") {
        if model.capturing { model.cancelCapture() } else { model.startCapture() }
      }
      .buttonStyle(.borderedProminent).tint(DesignSystem.pine)
      .disabled(!model.connected).accessibilityIdentifier("mouse.identifyButton")
    }
    .padding(14)
    .background(
      DesignSystem.mint.opacity(model.capturing ? 0.85 : 0.45),
      in: RoundedRectangle(cornerRadius: 14))
  }

}

private struct SensorControl: View {
  let sensor: Sensor
  let value: Int
  let showSensorNumber: Bool
  let apply: (Int) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(sensor.name).font(.headline)
        if showSensorNumber { Text("传感器 \(Int(sensor.number) + 1)").foregroundStyle(.secondary) }
      }
      HStack {
        if sensor.values.count > 1 {
          Slider(
            value: Binding(
              get: { Double(sensor.values.firstIndex(of: value) ?? 0) },
              set: { apply(sensor.values[Int($0.rounded())]) }
            ), in: 0...Double(sensor.values.count - 1), step: 1
          )
          .frame(maxWidth: .infinity).accessibilityLabel("硬件 DPI").accessibilityValue("\(value)")
        }
        Text("\(value) DPI").monospacedDigit().frame(width: sliderValueWidth, alignment: .trailing)
      }
    }
  }
}
