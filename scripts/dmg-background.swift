// Draws the DMG window background: swift scripts/dmg-background.swift <out.png> <scale>
// The layout (640×460 points, icons at x 170 and 470 y 170, readme at x 320 y 350) must match scripts/build-dmg.sh.
// shortcut: light background, checked only in light mode; in dark mode the Finder writes the icon names in white. Revisit if dark-mode users complain.
import AppKit

let args = CommandLine.arguments
let scale = CGFloat(Double(args[2]) ?? 1)
let size = NSSize(width: 640, height: 460)
let navy = NSColor(srgbRed: 21 / 255, green: 28 / 255, blue: 44 / 255, alpha: 1)
let yellow = NSColor(srgbRed: 245 / 255, green: 190 / 255, blue: 40 / 255, alpha: 1)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
// flipped: y grows downwards like the Finder's icon positions
let flip = NSAffineTransform(); flip.translateX(by: 0, yBy: size.height); flip.scaleX(by: 1, yBy: -1); flip.concat()

NSColor(srgbRed: 246 / 255, green: 247 / 255, blue: 250 / 255, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

func text(_ s: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let style = NSMutableParagraphStyle(); style.alignment = .center
    let attr = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                          .foregroundColor: color, .paragraphStyle: style])
    NSGraphicsContext.current?.saveGraphicsState()
    // text must be drawn unflipped
    let t = NSAffineTransform(); t.translateX(by: 0, yBy: y * 2 + size * 1.25); t.scaleX(by: 1, yBy: -1); t.concat()
    attr.draw(in: NSRect(x: 0, y: y, width: 640, height: size * 1.25))
    NSGraphicsContext.current?.restoreGraphicsState()
}

text("Trascina CheCavo nella cartella Applicazioni", y: 36, size: 20, weight: .semibold, color: navy)

// the arrow between the two icons
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 262, y: 170)); arrow.line(to: NSPoint(x: 372, y: 170))
arrow.lineWidth = 6; arrow.lineCapStyle = .round
yellow.setStroke(); arrow.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 356, y: 152)); head.line(to: NSPoint(x: 378, y: 170)); head.line(to: NSPoint(x: 356, y: 188))
head.lineWidth = 6; head.lineCapStyle = .round; head.lineJoinStyle = .round
head.stroke()

text("La prima volta macOS la blocca: le istruzioni sono qui sotto, nel Leggimi.", y: 272, size: 13, weight: .regular,
     color: navy.withAlphaComponent(0.6))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
