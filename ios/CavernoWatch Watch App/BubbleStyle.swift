import SwiftUI

/// The bubble palette, taken from the phone's own tokens
/// (`lib/core/theme/app_theme.dart` and `app_tokens.dart`) so the wrist and
/// the phone are recognisably the same app rather than two designs that
/// happen to share a name.
enum BubbleStyle {
  /// `accent` in the Flutter theme.
  static let outgoing = Color(red: 0x02 / 255, green: 0x88 / 255, blue: 0xD1 / 255)
  /// `surface3` in the dark palette; the watch has no light mode to serve.
  static let incoming = Color(red: 0x26 / 255, green: 0x26 / 255, blue: 0x2B / 255)
}

/// A Messages-style bubble: rounded on three corners, tailed on the bottom
/// corner nearest its sender.
///
/// Drawn as one continuous path rather than a rounded rect with the tail laid
/// over it. Two overlapping subpaths only merge into one shape when both are
/// wound the same way, and the failure mode — a hairline seam, or the overlap
/// punched out entirely — is invisible until it renders on a device.
struct BubbleShape: Shape {
  var isOutgoing: Bool

  private let corner: CGFloat = 12
  private let tail: CGFloat = 5

  func path(in rect: CGRect) -> Path {
    let radius = max(0, min(corner, min(rect.width - tail, rect.height) / 2))
    let left = rect.minX + tail
    let right = rect.maxX
    let top = rect.minY
    let bottom = rect.maxY

    // Built tail-on-the-leading-edge, then mirrored for an outgoing bubble.
    var path = Path()
    path.move(to: CGPoint(x: left, y: top + radius))
    path.addArc(
      center: CGPoint(x: left + radius, y: top + radius), radius: radius,
      startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
    path.addLine(to: CGPoint(x: right - radius, y: top))
    path.addArc(
      center: CGPoint(x: right - radius, y: top + radius), radius: radius,
      startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
    path.addLine(to: CGPoint(x: right, y: bottom - radius))
    path.addArc(
      center: CGPoint(x: right - radius, y: bottom - radius), radius: radius,
      startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
    path.addLine(to: CGPoint(x: left + radius, y: bottom))
    // The tail: the bottom edge runs out to a tip level with it, then hooks
    // back up the body's edge.
    path.addLine(to: CGPoint(x: rect.minX, y: bottom))
    path.addQuadCurve(
      to: CGPoint(x: left, y: bottom - radius),
      control: CGPoint(x: left - tail * 0.35, y: bottom - radius * 0.45))
    path.closeSubpath()

    guard isOutgoing else { return path }
    return path.applying(
      CGAffineTransform(translationX: rect.minX + rect.maxX, y: 0)
        .scaledBy(x: -1, y: 1)
    )
  }
}
