import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ScaleMode: String, CaseIterable, Identifiable, Sendable {
    case fill, fit, stretch
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .fill: "Fill (crop)"
        case .fit: "Fit (letterbox)"
        case .stretch: "Stretch"
        }
    }
}

/// Source media decoded into full-canvas frames at their native size.
public struct SourceMedia {
    public var frames: [CGImage]
    /// Seconds each frame stays on screen.
    public var delays: [Double]
    public var pixelSize: CGSize { frames.first.map { CGSize(width: $0.width, height: $0.height) } ?? .zero }
}

/// Frames rendered at the screen's 240x135 resolution, ready to encode.
public struct LCDImage {
    public var profile: KeyboardProfile
    public var frames: [CGImage]
    public var delays: [Double]
    /// Frame count of the source before any reduction to fit the limit.
    public var sourceFrameCount: Int

    public var totalDuration: Double { delays.reduce(0, +) }
    public var pageCount: Int { profile.pageCount(frames: frames.count) }
    /// Rough wall-clock upload time. Measured on hardware: ~150 ms per 4 KB page including the ack.
    public var estimatedUploadSeconds: Double { Double(pageCount) * 0.15 + 1 }
}

// MARK: Loading

public enum MediaLoader {
    /// Loads GIF / PNG / JPEG / HEIC / WebP / APNG via ImageIO, or a video via AVFoundation.
    public static func load(_ url: URL, videoFPS: Double = 15, maxFrames: Int = KeyboardProfile.f108Pro.maxFrames) async throws -> SourceMedia {
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        if let type, type.conforms(to: .movie) || type.conforms(to: .video) {
            return try await loadVideo(url, fps: videoFPS, maxFrames: maxFrames)
        }
        return try loadImage(url)
    }

    static func loadImage(_ url: URL) throws -> SourceMedia {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw AulaError.badBuffer("could not read \(url.lastPathComponent)")
        }
        let count = CGImageSourceGetCount(src)
        guard count > 0 else { throw AulaError.badBuffer("\(url.lastPathComponent) has no frames") }

        var frames: [CGImage] = []
        var delays: [Double] = []
        // ImageIO composites animated GIF/APNG/WebP frames (disposal, partial frames) for us.
        for i in 0..<count {
            guard let img = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            frames.append(img)
            delays.append(frameDelay(src, i))
        }
        guard !frames.isEmpty else { throw AulaError.badBuffer("could not decode \(url.lastPathComponent)") }
        if frames.count == 1 { delays = [1.0] }
        return SourceMedia(frames: frames, delays: delays)
    }

    private static func frameDelay(_ src: CGImageSource, _ i: Int) -> Double {
        let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any] ?? [:]
        let dicts: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
        ]
        for (dictKey, unclamped, clamped) in dicts {
            guard let d = props[dictKey] as? [CFString: Any] else { continue }
            let v = (d[unclamped] as? Double) ?? (d[clamped] as? Double) ?? 0
            // Browsers treat <= 10 ms as 100 ms; so do we.
            return v <= 0.011 ? 0.1 : v
        }
        return 0.1
    }

    static func loadVideo(_ url: URL, fps: Double, maxFrames: Int) async throws -> SourceMedia {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw AulaError.badBuffer("video has no duration") }

        // Never sample more than the keyboard can store.
        let count = max(1, min(maxFrames, Int((duration * fps).rounded(.down))))
        let step = duration / Double(count)

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = CMTime(seconds: step / 2, preferredTimescale: 600)
        gen.maximumSize = CGSize(width: 960, height: 540)

        var frames: [CGImage] = []
        for i in 0..<count {
            let t = CMTime(seconds: Double(i) * step, preferredTimescale: 600)
            let (img, _) = try await gen.image(at: t)
            frames.append(img)
        }
        return SourceMedia(frames: frames, delays: Array(repeating: step, count: frames.count))
    }
}

// MARK: Rendering + encoding

extension LCDImage {
    /// Scales every frame to 240x135 and, if needed, drops frames evenly so the result
    /// fits the 141-frame limit (the dropped frames' time is folded into their neighbours
    /// so playback speed is preserved).
    public static func render(_ media: SourceMedia, mode: ScaleMode, background: CGColor? = nil,
                              speed: Double = 1.0, profile: KeyboardProfile = .f108Pro) throws -> LCDImage {
        let n = media.frames.count
        var picked: [(CGImage, Double)] = []
        if n <= profile.maxFrames {
            picked = zip(media.frames, media.delays).map { ($0, $1) }
        } else {
            let keep = profile.maxFrames
            for k in 0..<keep {
                let lo = k * n / keep, hi = (k + 1) * n / keep
                picked.append((media.frames[lo], media.delays[lo..<hi].reduce(0, +)))
            }
        }

        let bg = background ?? CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        var frames: [CGImage] = []
        for (img, _) in picked {
            guard let r = renderFrame(img, mode: mode, background: bg, profile: profile) else {
                throw AulaError.badBuffer("failed to render frame")
            }
            frames.append(r)
        }
        let s = max(speed, 0.05)
        return LCDImage(profile: profile, frames: frames, delays: picked.map { $0.1 / s }, sourceFrameCount: n)
    }

    static func renderFrame(_ img: CGImage, mode: ScaleMode, background: CGColor, profile: KeyboardProfile) -> CGImage? {
        let w = profile.screenWidth, h = profile.screenHeight
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.setFillColor(background)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        let iw = CGFloat(img.width), ih = CGFloat(img.height)
        let rect: CGRect
        switch mode {
        case .stretch:
            rect = CGRect(x: 0, y: 0, width: w, height: h)
        case .fill, .fit:
            let sx = CGFloat(w) / iw, sy = CGFloat(h) / ih
            let s = mode == .fill ? max(sx, sy) : min(sx, sy)
            let dw = iw * s, dh = ih * s
            rect = CGRect(x: (CGFloat(w) - dw) / 2, y: (CGFloat(h) - dh) / 2, width: dw, height: dh)
        }
        ctx.draw(img, in: rect)
        return ctx.makeImage()
    }

    /// Solid color, handy for testing the upload path.
    public static func solid(red: UInt8, green: UInt8, blue: UInt8, profile: KeyboardProfile = .f108Pro) -> LCDImage {
        let c = CGColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
        let img = Canvas.draw(profile: profile) { ctx, w, h in
            ctx.setFillColor(c)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        return LCDImage(profile: profile, frames: [img], delays: [1], sourceFrameCount: 1)
    }

    /// Keyboard format: 256-byte header (frame count, per-frame delay in 20 ms units,
    /// 0xFF padding), then RGB565 little-endian frames, padded with 0xFF to 4 KB pages.
    public func encode() throws -> Data {
        guard !frames.isEmpty else { throw AulaError.badBuffer("no frames") }
        guard frames.count <= profile.maxFrames else { throw AulaError.tooManyFrames(frames.count, limit: profile.maxFrames) }

        var buf = [UInt8](repeating: 0xFF, count: pageCount * F108.pageSize)
        buf[0] = UInt8(frames.count)
        for (i, d) in delays.enumerated() {
            buf[1 + i] = UInt8(max(1, min(255, Int((d * 50).rounded()))))
        }

        let w = profile.screenWidth, h = profile.screenHeight
        let frameBytes = profile.frameBytes
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        for (fi, frame) in frames.enumerated() {
            rgba.withUnsafeMutableBytes { ptr in
                let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                    bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
                ctx.draw(frame, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            var o = F108.headerBytes + fi * frameBytes
            for p in 0..<(w * h) {
                let r = UInt16(rgba[p * 4]), g = UInt16(rgba[p * 4 + 1]), b = UInt16(rgba[p * 4 + 2])
                let px = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
                buf[o] = UInt8(px & 0xFF)
                buf[o + 1] = UInt8(px >> 8)
                o += 2
            }
        }
        return Data(buf)
    }
}

/// Small helper for drawing a single screen-sized frame.
enum Canvas {
    static func draw(profile: KeyboardProfile, _ body: (CGContext, Int, Int) -> Void) -> CGImage {
        let w = profile.screenWidth, h = profile.screenHeight
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        body(ctx, w, h)
        return ctx.makeImage()!
    }
}
