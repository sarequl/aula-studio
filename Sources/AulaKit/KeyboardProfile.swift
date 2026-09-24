import Foundation

/// Everything that differs between keyboard models in the AULA screen line.
///
/// The command set (begin/apply, lighting, clock, LCD header) is the vendor SDK shared
/// across the family; the USB ids, screen size and flash slot size are per model. Only
/// add a profile from a verified source (vendor `config.xml` or a hardware capture),
/// because `maxFrames` is what stops uploads from overwriting the menu graphics.
public struct KeyboardProfile: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let vendorID: Int
    public let productID: Int
    /// Ids the keyboard presents over Bluetooth / 2.4G, where the protocol is unavailable.
    public let wirelessVendorID: Int?
    public let wirelessProductID: Int?
    public let screenWidth: Int
    public let screenHeight: Int
    /// `gif_maxframes` from the vendor config. The firmware does NOT bounds-check.
    public let maxFrames: Int
    /// Whether someone has run this tool against the real hardware.
    public let verified: Bool

    public var screenSize: CGSize { CGSize(width: screenWidth, height: screenHeight) }
    var frameBytes: Int { screenWidth * screenHeight * 2 }
    var maxPages: Int { (F108.headerBytes + maxFrames * frameBytes + F108.pageSize - 1) / F108.pageSize }

    public func pageCount(frames: Int) -> Int {
        (F108.headerBytes + frames * frameBytes + F108.pageSize - 1) / F108.pageSize
    }

    public static let f108Pro = KeyboardProfile(
        id: "f108pro", name: "AULA F108 Pro",
        vendorID: 0x0C45, productID: 0x800A,
        wirelessVendorID: 0x05AC, wirelessProductID: 0x024F,
        screenWidth: 240, screenHeight: 135, maxFrames: 141, verified: true)

    public static let all: [KeyboardProfile] = [.f108Pro]
}
