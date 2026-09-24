// Generates Resources/AppIcon.icns: a keyboard-screen glyph on a dark rounded tile.
// Run: swift scripts/make-icon.swift
import AppKit

func render(_ px: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: px, height: px))
    img.lockFocus()
    let s = CGFloat(px)
    let r = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s), xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.17, blue: 0.22, alpha: 1), NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)])!
        .draw(in: r, angle: -90)

    // Screen
    let sw = s * 0.62, sh = sw * 135 / 240
    let screen = NSRect(x: (s - sw) / 2, y: s * 0.40, width: sw, height: sh)
    let sp = NSBezierPath(roundedRect: screen, xRadius: s * 0.03, yRadius: s * 0.03)
    NSGradient(colors: [NSColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 1), NSColor(red: 0.55, green: 0.25, blue: 1.0, alpha: 1), NSColor(red: 1.0, green: 0.35, blue: 0.55, alpha: 1)])!
        .draw(in: sp, angle: 20)
    NSColor.white.withAlphaComponent(0.25).setStroke()
    sp.lineWidth = s * 0.012
    sp.stroke()

    // Key row
    let keys = 6
    let gap = s * 0.02
    let kw = (sw - gap * CGFloat(keys - 1)) / CGFloat(keys)
    for i in 0..<keys {
        let k = NSRect(x: screen.minX + CGFloat(i) * (kw + gap), y: s * 0.2, width: kw, height: kw * 0.9)
        NSColor(white: 0.85, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: k, xRadius: s * 0.015, yRadius: s * 0.015).fill()
    }
    img.unlockFocus()
    return img
}

let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: tmp)
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    let img = render(px)
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    rep.size = NSSize(width: px, height: px)
    try! rep.representation(using: .png, properties: [:])!.write(to: tmp.appendingPathComponent("icon_\(name).png"))
}
try? FileManager.default.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
let p = Process()
p.launchPath = "/usr/bin/iconutil"
p.arguments = ["-c", "icns", tmp.path, "-o", "Resources/AppIcon.icns"]
p.launch(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")
