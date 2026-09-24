import Foundation

/// One physical key: where it sits (in key units, 1u = one letter key) and which LED it drives.
public struct KeyCap: Identifiable, Hashable, Sendable {
    public let light: UInt8
    public let label: String
    /// Short name used by the CLI (`esc`, `f1`, `a`, `space`, `num7`…).
    public let name: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public var id: UInt8 { light }
}

public struct KeyLayout: Sendable {
    public let keys: [KeyCap]
    public let widthUnits: Double
    public let heightUnits: Double

    public func key(named n: String) -> KeyCap? {
        let k = n.lowercased()
        return keys.first { $0.name == k }
    }

    /// AULA F108 Pro: full-size ANSI with numpad. Light indices from the vendor's
    /// rgb-keyboard.xml (light_index == key_index on this board).
    public static let f108Pro: KeyLayout = {
        var keys: [KeyCap] = []
        func row(_ y: Double, _ items: [(UInt8, String, String, Double)], startX: Double = 0, gap: [Int: Double] = [:], height: Double = 1) {
            var x = startX
            for (i, item) in items.enumerated() {
                x += gap[i] ?? 0
                keys.append(KeyCap(light: item.0, label: item.1, name: item.2, x: x, y: y, width: item.3, height: height))
                x += item.3
            }
        }
        // Function row. The cluster gaps match a standard ANSI board.
        row(0, [(1, "esc", "esc", 1), (2, "F1", "f1", 1), (3, "F2", "f2", 1), (4, "F3", "f3", 1), (5, "F4", "f4", 1),
                (6, "F5", "f5", 1), (7, "F6", "f6", 1), (8, "F7", "f7", 1), (9, "F8", "f8", 1),
                (10, "F9", "f9", 1), (11, "F10", "f10", 1), (12, "F11", "f11", 1), (13, "F12", "f12", 1),
                (112, "prt", "printscreen", 1), (113, "scr", "scrolllock", 1), (115, "pse", "pause", 1)],
            gap: [1: 1, 5: 0.5, 9: 0.5, 13: 0.25])
        row(1.25, [(19, "`", "grave", 1), (20, "1", "1", 1), (21, "2", "2", 1), (22, "3", "3", 1), (23, "4", "4", 1), (24, "5", "5", 1),
                   (25, "6", "6", 1), (26, "7", "7", 1), (27, "8", "8", 1), (28, "9", "9", 1), (29, "0", "0", 1), (30, "-", "minus", 1),
                   (31, "=", "equal", 1), (103, "⌫", "backspace", 2),
                   (116, "ins", "insert", 1), (117, "home", "home", 1), (118, "pgup", "pageup", 1),
                   (32, "num", "numlock", 1), (33, "/", "numslash", 1), (34, "*", "numstar", 1), (122, "-", "numminus", 1)],
            gap: [14: 0.25, 17: 0.25])
        row(2.25, [(37, "tab", "tab", 1.5), (38, "Q", "q", 1), (39, "W", "w", 1), (40, "E", "e", 1), (41, "R", "r", 1), (42, "T", "t", 1),
                   (43, "Y", "y", 1), (44, "U", "u", 1), (45, "I", "i", 1), (46, "O", "o", 1), (47, "P", "p", 1), (48, "[", "lbracket", 1),
                   (49, "]", "rbracket", 1), (67, "\\", "backslash", 1.5),
                   (119, "del", "delete", 1), (120, "end", "end", 1), (121, "pgdn", "pagedown", 1),
                   (50, "7", "num7", 1), (51, "8", "num8", 1), (52, "9", "num9", 1)],
            gap: [14: 0.25, 17: 0.25])
        keys.append(KeyCap(light: 123, label: "+", name: "numplus", x: 21.5, y: 2.25, width: 1, height: 2))
        row(3.25, [(55, "caps", "capslock", 1.75), (56, "A", "a", 1), (57, "S", "s", 1), (58, "D", "d", 1), (59, "F", "f", 1), (60, "G", "g", 1),
                   (61, "H", "h", 1), (62, "J", "j", 1), (63, "K", "k", 1), (64, "L", "l", 1), (65, ";", "semicolon", 1), (66, "'", "quote", 1),
                   (85, "enter", "enter", 2.25),
                   (68, "4", "num4", 1), (69, "5", "num5", 1), (70, "6", "num6", 1)],
            gap: [13: 3.5])
        row(4.25, [(73, "shift", "lshift", 2.25), (74, "Z", "z", 1), (75, "X", "x", 1), (76, "C", "c", 1), (77, "V", "v", 1), (78, "B", "b", 1),
                   (79, "N", "n", 1), (80, "M", "m", 1), (81, ",", "comma", 1), (82, ".", "dot", 1), (83, "/", "slash", 1),
                   (84, "shift", "rshift", 2.75),
                   (101, "↑", "up", 1),
                   (86, "1", "num1", 1), (87, "2", "num2", 1), (88, "3", "num3", 1)],
            gap: [12: 1.25, 13: 1.25])
        keys.append(KeyCap(light: 106, label: "⏎", name: "numenter", x: 21.5, y: 4.25, width: 1, height: 2))
        row(5.25, [(91, "ctrl", "lctrl", 1.25), (92, "win", "lwin", 1.25), (93, "alt", "lalt", 1.25), (94, "", "space", 6.25),
                   (95, "alt", "ralt", 1.25), (96, "fn", "fn", 1.25), (97, "menu", "menu", 1.25), (98, "ctrl", "rctrl", 1.25),
                   (99, "←", "left", 1), (100, "↓", "down", 1), (102, "→", "right", 1),
                   (104, "0", "num0", 2), (105, ".", "numdot", 1)],
            gap: [8: 0.25, 11: 0.25])
        return KeyLayout(keys: keys, widthUnits: 22.5, heightUnits: 6.25)
    }()
}
