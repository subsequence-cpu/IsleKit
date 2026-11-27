import AppKit
import SwiftUI

public func ink(_ rgb: UInt32) -> Color {
  Color(
    .sRGB, red: Double(rgb >> 16) / 255, green: Double(rgb >> 8 & 255) / 255,
    blue: Double(rgb & 255) / 255, opacity: 1)
}
public let paper = ink(0xFFFCF3)
public let rail = ink(0xFAF7EF)
public let text = ink(0x463B32)
public let quiet = ink(0x695E51)
public let line = ink(0xDDD6C4)
public let pine = ink(0x246659)
public let mint = ink(0xC6E8D0)
public let white = ink(0xFFFEFA)
public let coral = ink(0xF08C75)
public struct Artwork: View {
  private static let resources: Bundle = {
    if let url = Bundle.main.url(
      forResource: "IsleKitModules_DesignSystem", withExtension: "bundle"),
      let bundle = Bundle(url: url)
    {
      return bundle
    }
    return Bundle.module
  }()
  public let name: String, size: CGFloat
  public init(name: String, size: CGFloat) {
    self.name = name
    self.size = size
  }
  public var body: some View {
    Group {
      if let url = Self.resources.url(forResource: name, withExtension: "svg", subdirectory: "Art"),
        let image = NSImage(contentsOf: url)
      {
        Image(nsImage: image).resizable()
      } else {
        Image(systemName: "square.grid.2x2").resizable()
      }
    }.aspectRatio(contentMode: .fit).frame(width: size, height: size)
  }
}

public struct AppMark: View {
  public init(size: CGFloat) { self.size = size }
  var size: CGFloat = 1024
  public var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.19, style: .continuous)
        .fill(ink(0xFAEDCD)).frame(width: size * 0.86, height: size * 0.86)
      Artwork(name: "toolbox", size: size * 0.79).offset(y: -size * 0.034)
    }.frame(width: size, height: size)
  }
}

public struct DotPaper: View {
  public init() {}
  public var body: some View {
    Canvas { context, size in
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ink(0xA9D7B6)))
      for y in stride(from: 6, to: size.height, by: 16) {
        for x in stride(from: 6, to: size.width, by: 16) {
          context.fill(
            Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)),
            with: .color(pine.opacity(0.15)))
        }
      }
    }
  }
}

public struct RibbonTitle: View {
  public init(title: String) { self.title = title }
  let title: String
  public var body: some View {
    Text(title).font(.system(size: 26, weight: .bold, design: .rounded))
      .padding(.vertical, 6).padding(.horizontal, 23)
      .background(coral, in: RoundedRectangle(cornerRadius: 5))
      .background {
        GeometryReader { box in
          Path { path in
            let w = box.size.width
            let h = box.size.height
            path.move(to: CGPoint(x: -11, y: 9))
            for point in [
              CGPoint(x: w + 11, y: 9), CGPoint(x: w + 5, y: h / 2 + 6),
              CGPoint(x: w + 11, y: h + 4), CGPoint(x: -11, y: h + 4),
              CGPoint(x: -5, y: h / 2 + 6),
            ] { path.addLine(to: point) }
            path.closeSubpath()
          }.fill(ink(0xCB6454))
        }
      }.padding(.horizontal, 11)
  }
}
