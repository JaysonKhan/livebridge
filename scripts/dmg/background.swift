// Draws the background of the installer window (660 × 420 pt) at 1× and 2×.
// Usage: swift scripts/dmg/background.swift <out-1x.png> <out-2x.png>
// The icons themselves are placed by Finder (scripts/dmg/settings.py); this only paints what sits behind them.
//
// Finder draws the icon names in black in light mode and in white in dark mode, whatever the background, so the
// band under the icons is a mid-tone teal on which both stay readable (about 4.5:1 each).
import AppKit

let width: CGFloat = 660
let height: CGFloat = 420
/// Centres of the two icons, in points from the top-left — must match `icon_locations` in settings.py.
let appCenter = CGPoint(x: 170, y: 196)
let applicationsCenter = CGPoint(x: 490, y: 196)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
  NSColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Converts a point measured from the top (as Finder does) to AppKit's bottom-left origin.
func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: height - p.y) }

func drawText(_ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, centerY: CGFloat) {
  let paragraph = NSMutableParagraphStyle()
  paragraph.alignment = .center
  let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: size, weight: weight),
    .foregroundColor: NSColor.white.withAlphaComponent(alpha),
    .paragraphStyle: paragraph,
  ]
  let string = NSAttributedString(string: text, attributes: attributes)
  let bounds = string.boundingRect(with: NSSize(width: width - 48, height: 200), options: [.usesLineFragmentOrigin])
  let rect = NSRect(x: 24, y: height - centerY - bounds.height / 2, width: width - 48, height: bounds.height)
  string.draw(with: rect, options: [.usesLineFragmentOrigin])
}

func render(scale: CGFloat, to path: String) {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
    bitsPerPixel: 0)!
  rep.size = NSSize(width: width, height: height)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

  // Base: the brand's night teal at the top, easing into the mid-tone band behind the icons and their names.
  let base = NSGradient(colors: [color(0x0B4A43), color(0x0E7568), color(0x0D6C60)], atLocations: [0, 0.62, 1],
    colorSpace: .sRGB)!
  base.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

  // A soft mint glow behind the arrow ties the two icons together.
  let glow = NSGradient(colors: [color(0x7FE0C8, 0.10), color(0x7FE0C8, 0)])!
  glow.draw(fromCenter: flip(CGPoint(x: 330, y: 196)), radius: 0, toCenter: flip(CGPoint(x: 330, y: 196)),
    radius: 240, options: [])

  // The arrow: a gentle arc from the app to Applications.
  let start = flip(CGPoint(x: appCenter.x + 82, y: appCenter.y))
  let end = flip(CGPoint(x: applicationsCenter.x - 86, y: applicationsCenter.y))
  let control = flip(CGPoint(x: 330, y: appCenter.y - 34))
  let arc = NSBezierPath()
  arc.move(to: start)
  arc.curve(to: end, controlPoint1: control, controlPoint2: control)
  arc.lineWidth = 4.5
  arc.lineCapStyle = .round
  color(0xFFFFFF, 0.92).setStroke()
  arc.stroke()
  // Arrowhead along the curve's final direction (from the control point to the end).
  let angle = atan2(end.y - control.y, end.x - control.x)
  let head = NSBezierPath()
  for side in [CGFloat(1), -1] {
    head.move(to: end)
    head.line(to: CGPoint(x: end.x - 15 * cos(angle + side * 0.55), y: end.y - 15 * sin(angle + side * 0.55)))
  }
  head.lineWidth = 4.5
  head.lineCapStyle = .round
  head.stroke()

  drawText("Drag JK - LiveBridge to Applications", size: 18, weight: .semibold, alpha: 1, centerY: 62)
  drawText("Opening it for the first time?", size: 12.5, weight: .semibold, alpha: 0.92, centerY: 342)
  drawText(
    "If macOS says it cannot verify the app, open System Settings → Privacy & Security\nand press Open Anyway next to JK - LiveBridge.",
    size: 11.5, weight: .regular, alpha: 0.85, centerY: 374)

  NSGraphicsContext.restoreGraphicsState()
  let png = rep.representation(using: .png, properties: [:])!
  try! png.write(to: URL(fileURLWithPath: path))
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
  FileHandle.standardError.write("usage: background.swift <out-1x.png> <out-2x.png>\n".data(using: .utf8)!)
  exit(2)
}
render(scale: 1, to: arguments[1])
render(scale: 2, to: arguments[2])
