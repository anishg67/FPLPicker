// Draws the app icon: the squad as a formation of dots on a dark pitch, in the
// app's own accent gradient. Regenerate after changing the palette with:
//
//   swiftc -O -o /tmp/icongen Tools/GenerateAppIcon.swift && \
//     (cd Sources/Assets.xcassets/AppIcon.appiconset && /tmp/icongen)
//
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

// The app's palette.
let deepPurple = rgb(0.10, 0.01, 0.17)
let purple     = rgb(0.26, 0.03, 0.38)
let mint       = rgb(0.00, 0.98, 0.60)
let cyan       = rgb(0.00, 0.66, 1.00)

// 1. Background gradient, top-left dark to bottom-right lighter.
let bg = CGGradient(colorsSpace: space, colors: [deepPurple, purple] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// 2. Soft accent glow behind the formation.
let glow = CGGradient(colorsSpace: space,
                      colors: [rgb(0.0, 0.98, 0.60, 0.20), rgb(0.0, 0.98, 0.60, 0.0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow,
                       startCenter: CGPoint(x: size / 2, y: size * 0.45), startRadius: 0,
                       endCenter: CGPoint(x: size / 2, y: size * 0.45), endRadius: size * 0.62,
                       options: [])

// 3. Pitch markings — faint, they only read at large sizes.
ctx.setStrokeColor(rgb(1, 1, 1, 0.10))
ctx.setLineWidth(9)
ctx.move(to: CGPoint(x: size * 0.08, y: size / 2))
ctx.addLine(to: CGPoint(x: size * 0.92, y: size / 2))
ctx.strokePath()
ctx.addEllipse(in: CGRect(x: size / 2 - 150, y: size / 2 - 150, width: 300, height: 300))
ctx.strokePath()
// Penalty boxes, top and bottom, kept clear of the corners iOS masks away.
ctx.stroke(CGRect(x: size / 2 - 230, y: size * 0.845, width: 460, height: 200))
ctx.stroke(CGRect(x: size / 2 - 230, y: -45, width: 460, height: 200))

// 4. The squad: a formation of dots, keeper at the top.
struct Dot { let x: Double; let y: Double; let r: Double }
var dots: [Dot] = []
let radius = 60.0
// Read top-down: keeper, three at the back, three in midfield, a lone striker.
let rows: [(count: Int, y: Double)] = [(1, 0.805), (3, 0.625), (3, 0.435), (1, 0.245)]
for row in rows {
    let spacing = 300.0
    let width = Double(row.count - 1) * spacing
    for index in 0..<row.count {
        let x = size / 2 - width / 2 + Double(index) * spacing
        dots.append(Dot(x: x, y: size * row.y, r: radius))
    }
}

// The lone striker wears the armband: drawn larger, with a ring.
let captainIndex = dots.count - 1

let accent = CGGradient(colorsSpace: space, colors: [mint, cyan] as CFArray, locations: [0, 1])!

for (index, dot) in dots.enumerated() {
    let r = index == captainIndex ? dot.r * 1.16 : dot.r

    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 34, color: rgb(0.0, 0.95, 0.75, 0.55))
    ctx.setFillColor(rgb(1, 1, 1, 1))
    ctx.fillEllipse(in: CGRect(x: dot.x - r, y: dot.y - r, width: r * 2, height: r * 2))
    ctx.restoreGState()

    // Clip to the dot and paint the shared accent gradient, so the formation
    // shifts from mint to cyan across the pitch rather than each dot repeating it.
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: dot.x - r, y: dot.y - r, width: r * 2, height: r * 2))
    ctx.clip()
    ctx.drawLinearGradient(accent,
                           start: CGPoint(x: 0, y: size),
                           end: CGPoint(x: size, y: 0),
                           options: [])
    ctx.restoreGState()

    if index == captainIndex {
        ctx.setStrokeColor(rgb(1, 1, 1, 0.92))
        ctx.setLineWidth(14)
        ctx.strokeEllipse(in: CGRect(x: dot.x - r - 26, y: dot.y - r - 26,
                                     width: (r + 26) * 2, height: (r + 26) * 2))
    }
}

guard let image = ctx.makeImage() else { fatalError("no image") }
let url = URL(fileURLWithPath: "icon-1024.png")
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("no destination")
}
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(url.path)")
