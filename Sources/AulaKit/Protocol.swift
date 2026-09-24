import Foundation

/// Wire-level constants for the AULA F108 Pro.
///
/// Protocol source: https://github.com/parsiya/f108-pro (Ghidra + USB capture of the
/// vendor Windows app, verified on hardware).
public enum F108 {
    public static let vendorID = 0x0C45   // Sonix, wired USB mode
    public static let productID = 0x800A

    /// Bluetooth / 2.4G presence. The vendor protocol does not work over these.
    public static let wirelessVendorID = 0x05AC
    public static let wirelessProductID = 0x024F

    /// Interface 3: 64-byte feature reports (begin/apply, lighting, clock, LCD header).
    static let configUsagePage = 0xFF13
    /// Interface 2: 4096-byte output reports on the interrupt OUT pipe (LCD pixels),
    /// 64-byte input reports as per-page acks.
    static let lcdUsagePage = 0xFF68

    static let reportSize = 64
    static let pageSize = 4096

    /// From the vendor app's config.xml (`cmd_delaytime`).
    static let commandDelay: TimeInterval = 0.035

    public static let screenWidth = 240
    public static let screenHeight = 135
    static let frameBytes = screenWidth * screenHeight * 2
    static let headerBytes = 256

    /// `gif_maxframes` from the vendor config. The firmware does NOT bounds-check:
    /// anything past this spills into the SPI flash region holding the knob-menu
    /// graphics and destroys them permanently. Never raise this.
    public static let maxFrames = 141
    static let maxPages = (headerBytes + maxFrames * frameBytes + pageSize - 1) / pageSize
}

public enum LightingMode: Int, CaseIterable, Identifiable, Sendable {
    case off, staticColor, singleOn, singleOff, glittering, falling, colourful, breath,
         spectrum, outward, scrolling, rolling, rotating, explode, launch, ripples,
         flowing, pulsating, tilt, shuttle

    public var id: Int { rawValue }

    public var name: String {
        switch self {
        case .off: "Off"
        case .staticColor: "Static"
        case .singleOn: "Single On"
        case .singleOff: "Single Off"
        case .glittering: "Glittering"
        case .falling: "Falling"
        case .colourful: "Colourful"
        case .breath: "Breath"
        case .spectrum: "Spectrum"
        case .outward: "Outward"
        case .scrolling: "Scrolling"
        case .rolling: "Rolling"
        case .rotating: "Rotating"
        case .explode: "Explode"
        case .launch: "Launch"
        case .ripples: "Ripples"
        case .flowing: "Flowing"
        case .pulsating: "Pulsating"
        case .tilt: "Tilt"
        case .shuttle: "Shuttle"
        }
    }

    public static func named(_ s: String) -> LightingMode? {
        let key = s.lowercased().replacingOccurrences(of: " ", with: "")
        return allCases.first { $0.name.lowercased().replacingOccurrences(of: " ", with: "") == key }
    }
}

public struct LightingConfig: Sendable, Equatable {
    public var mode: LightingMode
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    /// 0...5
    public var brightness: UInt8
    /// 0...5
    public var speed: UInt8
    /// 0 or 1
    public var direction: UInt8
    /// Rainbow instead of the single color.
    public var colorful: Bool

    public init(mode: LightingMode, red: UInt8 = 255, green: UInt8 = 255, blue: UInt8 = 255,
                brightness: UInt8 = 5, speed: UInt8 = 3, direction: UInt8 = 0, colorful: Bool = false) {
        self.mode = mode
        self.red = red
        self.green = green
        self.blue = blue
        self.brightness = min(brightness, 5)
        self.speed = min(speed, 5)
        self.direction = min(direction, 1)
        self.colorful = colorful
    }
}

public enum AulaError: LocalizedError {
    case notFound
    case wirelessOnly
    case interfaceMissing(String)
    case io(String, Int32)
    case tooManyFrames(Int)
    case badBuffer(String)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            "AULA F108 Pro not found. Connect it with the USB cable and set the mode switch to wired."
        case .wirelessOnly:
            "The keyboard is connected over Bluetooth/2.4G. Screen and lighting control only work in wired USB mode: plug in the cable and flip the mode switch to wired."
        case .interfaceMissing(let which):
            "Keyboard found but its \(which) interface is missing."
        case .io(let what, let code):
            String(format: "%@ failed (IOReturn 0x%08X)", what, UInt32(bitPattern: code))
        case .tooManyFrames(let n):
            "\(n) frames exceeds the keyboard's \(F108.maxFrames)-frame limit. Uploading more would overwrite the menu graphics in the keyboard's flash."
        case .badBuffer(let why):
            "Invalid image buffer: \(why)"
        }
    }
}
