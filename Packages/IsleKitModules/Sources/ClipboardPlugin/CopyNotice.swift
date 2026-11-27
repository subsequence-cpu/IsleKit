import SwiftUI

struct CopyNotice: View {
  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
      Text("已复制")
    }
    .font(.headline).foregroundStyle(.white)
    .fixedSize().padding(.horizontal, 14).padding(.vertical, 8)
    .background(Color(red: 0.14, green: 0.40, blue: 0.35), in: Capsule())
  }
}
