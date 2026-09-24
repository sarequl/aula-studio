import Foundation

/// What a physical key sends after remapping. Encoded as a 4-byte slot in the
/// keyboard's 576-byte remap table (one slot per light index).
public enum KeyAction: Hashable, Codable, Sendable {
    /// Factory behaviour.
    case none
    /// A keyboard usage (HID page 0x07), optionally with modifiers held.
    case key(usage: UInt8, modifiers: UInt8 = 0)
    /// The key becomes a modifier. Bits: 01 LCtrl 02 LShift 04 LAlt 08 LWin/Cmd, 10/20/40/80 the right-hand ones.
    case modifier(UInt8)
    /// Media / consumer usage (page 0x0C): play 0xCD, stop 0xB7, prev 0xB6, next 0xB5, vol+ 0xE9, vol- 0xEA, mute 0xE2.
    case consumer(UInt8)
    /// Vendor special functions, e.g. (0x01, 0x02) caps lock, (0x03, 0xFF) lock PC.
    case special(UInt8, UInt8)
    /// The key does nothing.
    case disabled

    var slot: [UInt8] {
        switch self {
        case .none: [0, 0, 0, 0]
        case .key(let u, let m): [0x02, m, u, 0]
        case .modifier(let bits): [0x02, bits, 0, 0]
        case .consumer(let c): [0x03, c, 0, 0]
        case .special(let a, let b): [0x01, a, b, 0]
        case .disabled: [0x02, 0, 0, 0]
        }
    }

    public static let leftCtrl = KeyAction.modifier(0x01)
    public static let leftShift = KeyAction.modifier(0x02)
    public static let leftAlt = KeyAction.modifier(0x04)
    public static let leftWin = KeyAction.modifier(0x08)
    public static let rightCtrl = KeyAction.modifier(0x10)
    public static let rightShift = KeyAction.modifier(0x20)
    public static let rightAlt = KeyAction.modifier(0x40)
    public static let rightWin = KeyAction.modifier(0x80)

    public static let playPause = KeyAction.consumer(0xCD)
    public static let stop = KeyAction.consumer(0xB7)
    public static let previousTrack = KeyAction.consumer(0xB6)
    public static let nextTrack = KeyAction.consumer(0xB5)
    public static let volumeUp = KeyAction.consumer(0xE9)
    public static let volumeDown = KeyAction.consumer(0xEA)
    public static let mute = KeyAction.consumer(0xE2)

    /// Names the CLI and UI accept for targets, besides plain key names from the layout.
    public static let namedTargets: [(String, KeyAction)] = [
        ("none", .none), ("disabled", .disabled),
        ("lctrl", .leftCtrl), ("lshift", .leftShift), ("lalt", .leftAlt), ("lwin", .leftWin),
        ("rctrl", .rightCtrl), ("rshift", .rightShift), ("ralt", .rightAlt), ("rwin", .rightWin),
        ("cmd", .leftWin), ("option", .leftAlt), ("ctrl", .leftCtrl), ("shift", .leftShift),
        ("play", .playPause), ("stop", .stop), ("prev", .previousTrack), ("next", .nextTrack),
        ("volup", .volumeUp), ("voldown", .volumeDown), ("mute", .mute),
        ("capslock", .special(0x01, 0x02)), ("numlock", .special(0x01, 0x01)), ("scrolllock", .special(0x01, 0x04)),
        ("lock", .special(0x03, 0xFF)), ("calculator", .special(0x03, 0x01)),
    ]

    /// Resolves a target name: a named target above, or a key from the layout.
    public static func named(_ name: String, layout: KeyLayout = .f108Pro) -> KeyAction? {
        let n = name.lowercased()
        if let t = namedTargets.first(where: { $0.0 == n }) { return t.1 }
        if let k = layout.key(named: n), let u = k.usage { return .key(usage: u) }
        return nil
    }
}

/// A full remap for one layer: light index → action. Keys absent keep factory behaviour.
public typealias KeyMap = [UInt8: KeyAction]

public enum RemapPresets {
    /// Cmd next to Space, Option outside it, like a Mac keyboard. Right Alt becomes Cmd, Menu becomes Option.
    public static let mac: KeyMap = [92: .leftAlt, 93: .leftWin, 95: .rightWin, 97: .rightAlt]
    /// Factory layout.
    public static let windows: KeyMap = [:]
}

extension KeyCap {
    /// HID keyboard usage (page 0x07) the key sends by default. Fn has none.
    public var usage: UInt8? { KeyLayout.usageByLight[light] }
}

extension KeyLayout {
    static let usageByLight: [UInt8: UInt8] = [
        1: 0x29, 2: 0x3A, 3: 0x3B, 4: 0x3C, 5: 0x3D, 6: 0x3E, 7: 0x3F, 8: 0x40, 9: 0x41, 10: 0x42, 11: 0x43, 12: 0x44, 13: 0x45,
        112: 0x46, 113: 0x47, 115: 0x48,
        19: 0x35, 20: 0x1E, 21: 0x1F, 22: 0x20, 23: 0x21, 24: 0x22, 25: 0x23, 26: 0x24, 27: 0x25, 28: 0x26, 29: 0x27, 30: 0x2D, 31: 0x2E,
        103: 0x2A, 116: 0x49, 117: 0x4A, 118: 0x4B, 32: 0x53, 33: 0x54, 34: 0x55, 122: 0x56,
        37: 0x2B, 38: 0x14, 39: 0x1A, 40: 0x08, 41: 0x15, 42: 0x17, 43: 0x1C, 44: 0x18, 45: 0x0C, 46: 0x12, 47: 0x13, 48: 0x2F, 49: 0x30,
        67: 0x31, 119: 0x4C, 120: 0x4D, 121: 0x4E, 50: 0x5F, 51: 0x60, 52: 0x61, 123: 0x57,
        55: 0x39, 56: 0x04, 57: 0x16, 58: 0x07, 59: 0x09, 60: 0x0A, 61: 0x0B, 62: 0x0D, 63: 0x0E, 64: 0x0F, 65: 0x33, 66: 0x34,
        85: 0x28, 68: 0x5C, 69: 0x5D, 70: 0x5E,
        73: 0xE1, 74: 0x1D, 75: 0x1B, 76: 0x06, 77: 0x19, 78: 0x05, 79: 0x11, 80: 0x10, 81: 0x36, 82: 0x37, 83: 0x38, 84: 0xE5,
        101: 0x52, 86: 0x59, 87: 0x5A, 88: 0x5B, 106: 0x58,
        91: 0xE0, 92: 0xE3, 93: 0xE2, 94: 0x2C, 95: 0xE6, 97: 0x65, 98: 0xE4, 99: 0x50, 100: 0x51, 102: 0x4F, 104: 0x62, 105: 0x63,
    ]
}
