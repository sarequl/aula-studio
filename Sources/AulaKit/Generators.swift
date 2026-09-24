import CoreGraphics
import CoreText
import Foundation

/// Things the app can draw itself, without any source file.
public enum Generators {

    public struct TextStyle: Sendable, Equatable {
        public var text: String
        public var fontName: String
        public var fontSize: CGFloat
        public var color: (r: UInt8, g: UInt8, b: UInt8)
        public var background: (r: UInt8, g: UInt8, b: UInt8)
        /// 0 = static; otherwise pixels per second scrolled right-to-left.
        public var scrollSpeed: Double
        public var fps: Double

        public init(text: String, fontName: String = "Helvetica-Bold", fontSize: CGFloat = 48,
                    color: (UInt8, UInt8, UInt8) = (255, 255, 255), background: (UInt8, UInt8, UInt8) = (0, 0, 0),
                    scrollSpeed: Double = 0, fps: Double = 20) {
            self.text = text
            self.fontName = fontName
            self.fontSize = fontSize
            self.color = color
            self.background = background
            self.scrollSpeed = scrollSpeed
            self.fps = fps
        }

        public static func == (a: TextStyle, b: TextStyle) -> Bool {
            a.text == b.text && a.fontName == b.fontName && a.fontSize == b.fontSize && a.color == b.color
                && a.background == b.background && a.scrollSpeed == b.scrollSpeed && a.fps == b.fps
        }
    }

    /// Renders text centred on the screen, or as a looping marquee when `scrollSpeed > 0`.
    /// A marquee is sized so one full pass fits the frame limit; the loop is seamless.
    public static func text(_ style: TextStyle, profile: KeyboardProfile = .f108Pro) -> LCDImage {
        let w = CGFloat(profile.screenWidth), h = CGFloat(profile.screenHeight)
        let fg = cg(style.color), bg = cg(style.background)
        func makeLine(_ size: CGFloat) -> (CTLine, CGRect) {
            let font = CTFontCreateWithName(style.fontName as CFString, size, nil)
            let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: fg]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: style.text, attributes: attrs as [NSAttributedString.Key: Any]))
            return (line, CTLineGetBoundsWithOptions(line, .useOpticalBounds))
        }
        var (line, bounds) = makeLine(style.fontSize)
        // Static text shrinks to fit the screen with a small margin; a marquee keeps its size.
        if style.scrollSpeed <= 0, bounds.width > w - 8, bounds.width > 0 {
            (line, bounds) = makeLine(max(8, floor(style.fontSize * (w - 8) / bounds.width)))
        }
        let textWidth = bounds.width

        func frame(offsetX: CGFloat) -> CGImage {
            Canvas.draw(profile: profile) { ctx, _, _ in
                ctx.setFillColor(bg)
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
                ctx.textPosition = CGPoint(x: offsetX, y: (h - bounds.height) / 2 - bounds.minY)
                CTLineDraw(line, ctx)
            }
        }

        guard style.scrollSpeed > 0, textWidth > 0 else {
            return LCDImage(profile: profile, frames: [frame(offsetX: (w - textWidth) / 2 - bounds.minX)],
                            delays: [1], sourceFrameCount: 1)
        }

        // One pass: text enters from the right edge and leaves fully on the left.
        let travel = w + textWidth
        let seconds = Double(travel) / style.scrollSpeed
        var count = Int((seconds * style.fps).rounded())
        count = max(2, min(profile.maxFrames, count))
        let delay = seconds / Double(count)
        let frames = (0..<count).map { i in
            frame(offsetX: w - CGFloat(i) / CGFloat(count) * travel - bounds.minX)
        }
        return LCDImage(profile: profile, frames: frames, delays: Array(repeating: delay, count: count), sourceFrameCount: count)
    }

    public enum Preset: String, CaseIterable, Identifiable, Sendable {
        case sunset, ocean, aurora, ember, mono, candy
        public var id: String { rawValue }
        public var name: String { rawValue.capitalized }
        var stops: [(UInt8, UInt8, UInt8)] {
            switch self {
            case .sunset: [(255, 94, 98), (255, 195, 113)]
            case .ocean: [(0, 82, 212), (67, 206, 162)]
            case .aurora: [(0, 255, 135), (96, 239, 255), (168, 85, 247)]
            case .ember: [(20, 0, 0), (255, 60, 0), (255, 200, 0)]
            case .mono: [(20, 20, 20), (200, 200, 200)]
            case .candy: [(255, 0, 128), (255, 140, 0), (0, 200, 255)]
            }
        }
    }

    /// A gradient that slowly cycles: `animated` produces a seamless 4 s loop.
    public static func gradient(_ preset: Preset, animated: Bool = true, profile: KeyboardProfile = .f108Pro) -> LCDImage {
        let colors = preset.stops.map(cg)
        let count = animated ? 48 : 1
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        // Three periods, one screen width each. The visible window slides by one period
        // over the loop and always stays inside the gradient, so the loop has no seam.
        let looped = colors + colors + colors + [colors[0]]
        let locations = (0..<looped.count).map { CGFloat($0) / CGFloat(looped.count - 1) }
        let grad = CGGradient(colorsSpace: space, colors: looped as CFArray, locations: locations)!
        let w = CGFloat(profile.screenWidth), h = CGFloat(profile.screenHeight)
        let frames = (0..<count).map { i in
            let shift = CGFloat(i) / CGFloat(count) * w
            return Canvas.draw(profile: profile) { ctx, _, _ in
                ctx.drawLinearGradient(grad, start: CGPoint(x: -w - shift, y: 0), end: CGPoint(x: 2 * w - shift, y: h),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
        }
        return LCDImage(profile: profile, frames: frames, delays: Array(repeating: 4.0 / Double(count), count: count), sourceFrameCount: count)
    }

    static func cg(_ c: (UInt8, UInt8, UInt8)) -> CGColor {
        CGColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: 1)
    }
}
