import SwiftUI

extension View {
  @ViewBuilder func historyKeyboardFocus() -> some View {
    if #available(macOS 14, *) {
      focusable().focusEffectDisabled()
    } else {
      focusable()
    }
  }
}
