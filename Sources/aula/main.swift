import AulaKit
import Foundation
import ImageIO

let usage = """
usage: aula [-v] <command>

  status                          show how the keyboard is connected
  clock                           sync the screen clock to this Mac
  screen <file> [fill|fit|stretch] [--speed X] [--fps N]
                                  upload a GIF / image / video to the screen
  screen --color RRGGBB           upload a solid color
  preview <file> <out.png|out.gif> [mode]
                                  render what the screen will show (no keyboard needed)
  text "Hello" [--font Name] [--size N] [--color RRGGBB] [--bg RRGGBB] [--scroll px/s] [--out file|send]
  gradient <sunset|ocean|aurora|ember|mono|candy> [--static] [--out file|send]
  light <mode> [RRGGBB] [--brightness 0-5] [--speed 0-5] [--dir 0|1] [--rainbow]
  modes                           list lighting modes
  keys <key=RRGGBB ...> [--all RRGGBB] [--brightness 0-5]
                                  per-key colors; keys not given are off (e.g. keys wasd=00FF00 esc=FF0000)
  keynames                        list key names for `keys` and `remap`
  remap <key=target ...> [--fn]   set the whole remap layer; keys not given return to factory
  remap --mac | --windows         Mac layout (cmd next to space) / factory layout
  remap --reset                   clear both layers
        targets: a key name, lctrl lshift lalt lwin rctrl rshift ralt rwin cmd option,
                 play stop prev next volup voldown mute, capslock numlock lock calculator, disabled

Wired USB mode only. Supported: \(KeyboardProfile.all.map(\.name).joined(separator: ", ")).
The screen holds a limited number of frames; longer media is thinned automatically.
"""

var args = Array(CommandLine.arguments.dropFirst())
let verbose = args.contains("-v")
args.removeAll { $0 == "-v" }

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}

func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

func parseHex(_ s: String) -> (UInt8, UInt8, UInt8)? {
    let h = s.hasPrefix("#") ? String(s.dropFirst()) : s
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
    return (UInt8(v >> 16), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
}

func openDevice() -> AulaDevice {
    do {
        let d = try AulaDevice()
        if verbose { d.log = { print("  \($0)") } }
        return d
    } catch { fail(error.localizedDescription) }
}

func loadLCD(_ path: String, mode: ScaleMode, speed: Double, fps: Double) async throws -> LCDImage {
    let media = try await MediaLoader.load(URL(fileURLWithPath: path), videoFPS: fps)
    let img = try LCDImage.render(media, mode: mode, speed: speed)
    print("source: \(Int(media.pixelSize.width))x\(Int(media.pixelSize.height)), \(media.frames.count) frames")
    if img.sourceFrameCount > img.frames.count {
        print("thinned to \(img.frames.count) frames to stay inside the keyboard's flash slot")
    }
    return img
}

func writePreview(_ img: LCDImage, to out: URL) throws {
    if out.pathExtension.lowercased() == "bin" {
        try img.encode().write(to: out)
        return
    }
    let isGIF = out.pathExtension.lowercased() == "gif"
    let count = isGIF ? img.frames.count : 1
    guard let dest = CGImageDestinationCreateWithURL(out as CFURL, (isGIF ? "com.compuserve.gif" : "public.png") as CFString, count, nil) else {
        fail("cannot write \(out.path)")
    }
    if isGIF {
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    }
    for i in 0..<count {
        let props = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: img.delays[i]]] as CFDictionary
        CGImageDestinationAddImage(dest, img.frames[i], isGIF ? props : nil)
    }
    CGImageDestinationFinalize(dest)
}

guard let cmd = args.first else { print(usage); exit(0) }
args.removeFirst()

do {
    switch cmd {
    case "status":
        switch detectKeyboard() {
        case (let p, .wired)?: print("\(p.name) on USB: ready")
        case (let p, _)?: print("\(p.name) on Bluetooth/2.4G: connect the USB cable and switch to wired mode to configure")
        case nil: print("not found")
        }

    case "clock":
        try openDevice().syncClock()
        print("clock synced to \(Date().formatted(date: .abbreviated, time: .standard))")

    case "modes":
        for m in LightingMode.allCases { print(m.name.lowercased().replacingOccurrences(of: " ", with: "")) }

    case "keynames":
        print(KeyLayout.f108Pro.keys.map(\.name).joined(separator: " "))

    case "keys":
        let brightness = UInt8(option("--brightness") ?? "5") ?? 5
        var colors: [UInt8: (r: UInt8, g: UInt8, b: UInt8)] = [:]
        let layout = KeyLayout.f108Pro
        if let all = option("--all").flatMap(parseHex) {
            for k in layout.keys { colors[k.light] = all }
        }
        for a in args {
            let parts = a.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let c = parseHex(String(parts[1])) else { fail("bad assignment \(a); use key=RRGGBB") }
            let names = String(parts[0]).lowercased()
            // A run of single letters like "wasd" means each letter.
            let list = layout.key(named: names) != nil ? [names] : names.map { String($0) }
            for n in list {
                guard let k = layout.key(named: n) else { fail("unknown key \(n); see `aula keynames`") }
                colors[k.light] = c
            }
        }
        try openDevice().setPerKeyColors(colors, brightness: brightness)
        print("\(colors.count) keys set")

    case "remap":
        let layout = KeyLayout.f108Pro
        let dev = openDevice()
        if flag("--reset") {
            try dev.setRemap([:], fnLayer: false)
            try dev.setRemap([:], fnLayer: true)
            print("both layers reset to factory")
            break
        }
        let fn = flag("--fn")
        var map: KeyMap = flag("--mac") ? RemapPresets.mac : [:]
        _ = flag("--windows")
        for a in args {
            let parts = a.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let k = layout.key(named: String(parts[0])) else { fail("unknown key in \(a); see `aula keynames`") }
            guard let t = KeyAction.named(String(parts[1])) else { fail("unknown target in \(a)") }
            map[k.light] = t
        }
        try dev.setRemap(map, fnLayer: fn)
        print("\(fn ? "FN" : "normal") layer: \(map.count) keys remapped, the rest factory")

    case "light":
        guard let name = args.first, let mode = LightingMode.named(name) else { fail("unknown mode; see `aula modes`") }
        args.removeFirst()
        let brightness = UInt8(option("--brightness") ?? "5") ?? 5
        let speed = UInt8(option("--speed") ?? "3") ?? 3
        let dir = UInt8(option("--dir") ?? "0") ?? 0
        let rainbow = flag("--rainbow")
        let (r, g, b) = args.first.flatMap(parseHex) ?? (255, 255, 255)
        try openDevice().setLighting(LightingConfig(mode: mode, red: r, green: g, blue: b, brightness: brightness,
                                                    speed: speed, direction: dir, colorful: rainbow))
        print("lighting set: \(mode.name)")

    case "preview":
        let speed = Double(option("--speed") ?? "1") ?? 1
        let fps = Double(option("--fps") ?? "15") ?? 15
        guard args.count >= 2 else { fail(usage) }
        let mode = args.count > 2 ? (ScaleMode(rawValue: args[2]) ?? .fill) : .fill
        let img = try await loadLCD(args[0], mode: mode, speed: speed, fps: fps)
        let data = try img.encode()
        try writePreview(img, to: URL(fileURLWithPath: args[1]))
        print("\(img.frames.count) frames, \(String(format: "%.1f", img.totalDuration)) s loop, \(data.count) bytes, \(img.pageCount) pages")
        print("preview written to \(args[1])")

    case "text", "gradient":
        let out = option("--out") ?? "send"
        let img: LCDImage
        if cmd == "text" {
            guard let t = args.first else { fail(usage) }
            var st = Generators.TextStyle(text: t)
            if let f = option("--font") { st.fontName = f }
            if let n = option("--size").flatMap(Double.init) { st.fontSize = n }
            if let c = option("--color").flatMap(parseHex) { st.color = c }
            if let c = option("--bg").flatMap(parseHex) { st.background = c }
            if let v = option("--scroll").flatMap(Double.init) { st.scrollSpeed = v }
            img = Generators.text(st)
        } else {
            guard let name = args.first, let p = Generators.Preset(rawValue: name) else { fail("unknown preset") }
            img = Generators.gradient(p, animated: !flag("--static"))
        }
        if out == "send" {
            let data = try img.encode()
            try openDevice().uploadScreen(data) { s, t in if s == t { print("\(t) pages sent") } }
        } else {
            try writePreview(img, to: URL(fileURLWithPath: out))
        }

    case "screen":
        let speed = Double(option("--speed") ?? "1") ?? 1
        let fps = Double(option("--fps") ?? "15") ?? 15
        let img: LCDImage
        if let hex = option("--color") {
            guard let (r, g, b) = parseHex(hex) else { fail("bad color \(hex)") }
            img = LCDImage.solid(red: r, green: g, blue: b)
        } else {
            guard let path = args.first else { fail(usage) }
            let mode = args.count > 1 ? (ScaleMode(rawValue: args[1]) ?? .fill) : .fill
            img = try await loadLCD(path, mode: mode, speed: speed, fps: fps)
        }
        let data = try img.encode()
        let dev = openDevice()
        print("uploading \(img.frames.count) frames (\(img.pageCount) pages, ~\(Int(img.estimatedUploadSeconds)) s). Don't unplug.")
        let start = Date()
        try dev.uploadScreen(data) { sent, total in
            if sent == total || sent % 16 == 0 {
                print("\r  \(sent)/\(total) pages", terminator: "")
                fflush(stdout)
            }
        }
        print("\ndone in \(Int(Date().timeIntervalSince(start))) s. The keyboard shows a progress bar while it writes flash.")

    default:
        print(usage)
        exit(1)
    }
} catch {
    fail("error: \(error.localizedDescription)")
}
