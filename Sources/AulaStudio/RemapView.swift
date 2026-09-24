import AppKit
import AulaKit
import SwiftUI

// MARK: Model types

/// One remap layer: light index → action. (`KeyMap` in this module is the per-key color map.)
typealias RemapTable = AulaKit.KeyMap

enum RemapLayer: String, CaseIterable, Identifiable, Codable {
    case normal, fn
    var id: String { rawValue }
    var title: String { self == .normal ? "Normal" : "Fn layer" }
    var name: String { self == .normal ? "Normal layer" : "Fn layer" }
}

enum RemapPreset: String, CaseIterable, Identifiable {
    case mac, windows, capsCtrl, capsEsc, swapCtrlCaps
    var id: String { rawValue }

    var title: String {
        switch self {
        case .mac: "Mac layout"
        case .windows: "Windows layout"
        case .capsCtrl: "Caps Lock → Ctrl"
        case .capsEsc: "Caps Lock → Esc"
        case .swapCtrlCaps: "Swap Ctrl and Caps"
        }
    }

    var help: String {
        switch self {
        case .mac: "⌘ next to the space bar and ⌥ outside it, like a Mac keyboard"
        case .windows: "The factory layout, with no changes"
        case .capsCtrl: "Caps Lock becomes a second Control key"
        case .capsEsc: "Caps Lock becomes Esc"
        case .swapCtrlCaps: "Caps Lock becomes Control and left Control becomes Caps Lock"
        }
    }

    var map: RemapTable {
        let caps = RemapText.light("capslock"), ctrl = RemapText.light("lctrl")
        switch self {
        case .mac: return RemapPresets.mac
        case .windows: return RemapPresets.windows
        case .capsCtrl: return [caps: .leftCtrl]
        case .capsEsc: return [caps: .key(usage: 0x29)]
        case .swapCtrlCaps: return [caps: .leftCtrl, ctrl: RemapText.capsLock]
        }
    }

    /// Names accepted by `-selftest-remap`.
    init?(flag: String) {
        switch flag.lowercased() {
        case "mac": self = .mac
        case "windows": self = .windows
        case "caps", "caps-ctrl": self = .capsCtrl
        case "caps-esc": self = .capsEsc
        case "swap": self = .swapCtrlCaps
        default: return nil
        }
    }
}

/// Names and short labels for keys and actions.
enum RemapText {
    static let layout = KeyLayout.f108Pro
    static let capsLock = KeyAction.special(0x01, 0x02)

    static func light(_ name: String) -> UInt8 { layout.key(named: name)?.light ?? 0 }

    static let byUsage: [UInt8: KeyCap] = Dictionary(layout.keys.compactMap { k in k.usage.map { ($0, k) } },
                                                     uniquingKeysWith: { a, _ in a })

    private static let keyNames: [String: String] = [
        "esc": "Esc", "printscreen": "Print Screen", "scrolllock": "Scroll Lock", "pause": "Pause",
        "backspace": "Backspace", "insert": "Insert", "home": "Home", "pageup": "Page Up", "numlock": "Num Lock",
        "tab": "Tab", "delete": "Delete", "end": "End", "pagedown": "Page Down", "capslock": "Caps Lock",
        "enter": "Enter", "lshift": "Left Shift", "rshift": "Right Shift", "numenter": "Num Enter",
        "up": "↑ Up", "down": "↓ Down", "left": "← Left", "right": "→ Right",
        "lctrl": "Left Ctrl", "lwin": "Win", "lalt": "Left Alt", "space": "Space", "ralt": "Right Alt",
        "fn": "Fn", "menu": "Menu", "rctrl": "Right Ctrl",
    ]

    /// A physical key's name, e.g. "Win", "Caps Lock", "Num 7".
    static func name(_ k: KeyCap) -> String {
        if let n = keyNames[k.name] { return n }
        if k.name.hasPrefix("num") { return "Num \(k.label)" }
        return k.label
    }

    /// Left-hand modifier bits with their Mac name, Windows name and symbol, in Apple's display order.
    static let modifiers: [(bit: UInt8, mac: String, win: String, symbol: String)] = [
        (0x01, "Control", "Ctrl", "⌃"), (0x04, "Option", "Alt", "⌥"), (0x02, "Shift", "Shift", "⇧"), (0x08, "Command", "Win", "⌘"),
    ]

    /// Symbols for a modifier bitmask, either hand.
    static func symbols(_ bits: UInt8) -> String {
        modifiers.filter { bits & ($0.bit | $0.bit << 4) != 0 }.map(\.symbol).joined()
    }

    private static let consumer: [UInt8: (short: String, long: String)] = [
        0xCD: ("Play", "Play/Pause"), 0xB7: ("Stop", "Stop"), 0xB6: ("Prev", "Previous Track"), 0xB5: ("Next", "Next Track"),
        0xE9: ("Vol+", "Volume Up"), 0xEA: ("Vol−", "Volume Down"), 0xE2: ("Mute", "Mute"),
    ]

    private static let special: [UInt16: (short: String, long: String)] = [
        0x0102: ("Caps", "Caps Lock"), 0x0101: ("Num", "Num Lock"), 0x0104: ("Scroll", "Scroll Lock"),
        0x03FF: ("Lock", "Lock PC"), 0x0301: ("Calc", "Calculator"),
    ]

    private static func hex(_ v: UInt8) -> String { String(format: "0x%02X", v) }

    private static func keyLabel(_ usage: UInt8) -> String {
        guard let k = byUsage[usage] else { return hex(usage) }
        return k.label.isEmpty ? "Space" : k.label
    }

    /// The label drawn on a remapped key cap, e.g. "⌘", "Vol+", "A", "off". nil for factory behaviour.
    static func short(_ a: KeyAction) -> String? {
        switch a {
        case .none: return nil
        case .disabled: return "off"
        case .key(let u, let m): return symbols(m) + keyLabel(u)
        case .modifier(let b): return symbols(b)
        case .consumer(let c): return consumer[c]?.short ?? hex(c)
        case .special(let x, let y): return special[UInt16(x) << 8 | UInt16(y)]?.short ?? "\(hex(x)) \(hex(y))"
        }
    }

    /// A readable name for an action, e.g. "⌥ Option", "Right ⌘ Command", "Volume Up", "⌘C".
    static func long(_ a: KeyAction) -> String {
        switch a {
        case .none: return "Default"
        case .disabled: return "Disabled"
        case .key(let u, let m):
            let base = byUsage[u].map(name) ?? hex(u)
            return m == 0 ? base : symbols(m) + base
        case .modifier(let b):
            let right = b >= 0x10 && b & 0x0F == 0
            let bit = right ? b >> 4 : b
            guard let m = modifiers.first(where: { $0.bit == bit }) else { return symbols(b) }
            return (right ? "Right " : "") + "\(m.symbol) \(m.mac)"
        case .consumer(let c): return consumer[c]?.long ?? "Media \(hex(c))"
        case .special(let x, let y): return special[UInt16(x) << 8 | UInt16(y)]?.long ?? "Special \(hex(x)) \(hex(y))"
        }
    }

    /// nil when the action is the key's factory behaviour.
    static func normalized(_ a: KeyAction?, for k: KeyCap) -> KeyAction? {
        guard let a, a != .none else { return nil }
        if case .key(let u, 0) = a, u == k.usage { return nil }
        return a
    }
}

/// What is written to Remaps.json next to the library folder. Keys are layout names.
private struct RemapFile: Codable {
    var normal: [String: KeyAction]
    var fn: [String: KeyAction]
}

// MARK: Model logic

extension AppModel {
    func remap(_ layer: RemapLayer) -> RemapTable { layer == .normal ? remapNormal : remapFn }

    func setRemap(_ layer: RemapLayer, _ table: RemapTable) {
        guard remap(layer) != table else { return }
        if layer == .normal { remapNormal = table } else { remapFn = table }
    }

    var currentRemap: RemapTable { remap(remapLayer) }

    func setAction(_ a: KeyAction?, for k: KeyCap) {
        var t = currentRemap
        t[k.light] = RemapText.normalized(a, for: k)
        setRemap(remapLayer, t)
    }

    func applyRemapPreset(_ p: RemapPreset) {
        remapLayer = .normal
        setRemap(.normal, p.map)
    }

    private var remapsURL: URL? { sidecarURL("Remaps.json") }

    func loadRemaps() {
        func lights(_ named: [String: KeyAction]) -> RemapTable {
            var out: RemapTable = [:]
            for (n, a) in named { if let k = RemapText.layout.key(named: n) { out[k.light] = a } }
            return out
        }
        if let url = remapsURL, let data = try? Data(contentsOf: url),
           let file = try? JSONDecoder().decode(RemapFile.self, from: data) {
            remapNormal = lights(file.normal)
            remapFn = lights(file.fn)
        }
        remapLoaded = true
        // `-selftest-remap mac|caps` loads a preset at launch so the canvas shows remapped keys (used for screenshots).
        // It is only sent if "Apply as you change" is on and the keyboard is wired, which it never is at launch.
        if let flag = Self.remapDefaults.string(forKey: "selftest-remap"), let p = RemapPreset(flag: flag) {
            applyRemapPreset(p)
        }
        if Self.remapDefaults.string(forKey: "remap-layer")?.lowercased() == "fn" { remapLayer = .fn }
    }

    private static var remapDefaults: UserDefaults { .standard }

    private func saveRemapsFile() {
        guard let url = remapsURL else { return }
        func names(_ t: RemapTable) -> [String: KeyAction] {
            var out: [String: KeyAction] = [:]
            for k in RemapText.layout.keys { if let a = t[k.light] { out[k.name] = a } }
            return out
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try enc.encode(RemapFile(normal: names(remapNormal), fn: names(remapFn))).write(to: url, options: .atomic)
        } catch {
            show("Could not save remaps: \(error.localizedDescription)", error: true)
        }
    }

    /// Debounced: saves both layers and, with "Apply as you change" on, sends the layers that changed.
    func remapChanged(_ layer: RemapLayer) {
        guard remapLoaded else { return }
        remapDirty.insert(layer)
        remapTask?.cancel()
        remapTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let layers = remapDirty
            remapDirty = []
            saveRemapsFile()
            guard liveRemap, isWired else { return }
            while busy {
                try? await Task.sleep(for: .milliseconds(150))
                if Task.isCancelled { return }
            }
            let maps = RemapLayer.allCases.filter(layers.contains).map { ($0, remap($0)) }
            withDevice("", quiet: true) { dev in
                for (l, m) in maps { try dev.setRemap(m, fnLayer: l == .fn) }
            }
        }
    }

    func applyRemap(_ layer: RemapLayer) {
        guard isWired else { showNotWired(); return }
        let map = remap(layer)
        let n = map.count
        let label = n == 0 ? "\(layer.name) set to the factory layout"
            : "\(layer.name) sent, \(n) \(n == 1 ? "key" : "keys") remapped"
        withDevice(label) { try $0.setRemap(map, fnLayer: layer == .fn) }
    }

    /// Sends empty maps for both layers, then clears the editor to match.
    func resetKeyboardRemaps() {
        guard isWired else { showNotWired(); return }
        withDevice("Both layers are back to the factory layout", onSuccess: {
            self.remapNormal = [:]
            self.remapFn = [:]
            // Already sent; only the file needs updating.
            self.remapTask?.cancel()
            self.remapDirty = []
            self.saveRemapsFile()
        }) { dev in
            try dev.setRemap([:], fnLayer: false)
            try dev.setRemap([:], fnLayer: true)
        }
    }
}

// MARK: Page

struct RemapView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: KeyCap?
    @State private var confirmingFactory = false

    var body: some View {
        @Bindable var model = model
        let map = model.currentRemap
        Page {
            WiredNotice(message: "Remaps are sent over USB. You can still edit them without it.")

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Picker("Layer", selection: $model.remapLayer) {
                        ForEach(RemapLayer.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Spacer(minLength: 0)
                    Text(map.isEmpty ? "Factory layout" : "\(map.count) \(map.count == 1 ? "key" : "keys") remapped")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                KeyboardCanvas(summary: map.isEmpty ? "No keys remapped" : "\(map.count) keys remapped",
                               selected: editing?.light,
                               face: { face($0, map) },
                               onTap: { editing = $0 })
                    .overlay {
                        GeometryReader { geo in
                            Color.clear
                                .popover(item: $editing,
                                         attachmentAnchor: .rect(.rect(editing.map { KeyboardCanvas.frame(of: $0, width: geo.size.width) } ?? .zero)),
                                         arrowEdge: .bottom) { k in
                                    RemapPicker(key: k) { editing = nil }
                                }
                        }
                        .allowsHitTesting(false)
                    }
                Text(model.remapLayer == .normal
                     ? "Click a key to choose what it sends. Remapped keys are highlighted."
                     : "Click a key to choose what it sends while Fn is held. Keys you leave alone keep their factory Fn function.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            EmbeddedForm {
                Section {
                    if map.isEmpty {
                        Text(model.remapLayer == .normal ? "No changes. Every key does what is printed on it."
                             : "No changes. Keys keep their factory Fn functions.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(RemapText.layout.keys.filter { map[$0.light] != nil }) { k in
                            ChangeRow(key: k, action: map[k.light] ?? .none)
                        }
                    }
                } header: {
                    HStack {
                        Text("Changes in \(model.remapLayer.name)")
                        Spacer()
                        Button("Reset Layer") { model.setRemap(model.remapLayer, [:]) }
                            .controlSize(.small)
                            .disabled(map.isEmpty)
                            .help("Return every key in this layer to its factory action")
                    }
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                        ForEach(RemapPreset.allCases) { p in
                            Button { model.applyRemapPreset(p) } label: {
                                Label(p.title, systemImage: "checkmark")
                                    .labelStyle(PresetLabelStyle(active: model.remapNormal == p.map))
                                    .frame(maxWidth: .infinity)
                            }
                            .help(p.help)
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Presets")
                } footer: {
                    Text("A preset replaces the Normal layer. Mac layout puts ⌘ next to the space bar and ⌥ outside it.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Apply as you change", isOn: $model.liveRemap)
                    LabeledContent("Factory layout") {
                        Button("Reset Keyboard…") { confirmingFactory = true }
                            .disabled(!model.isWired || model.busy)
                            .help(model.isWired ? "Clear the remaps on both layers of the keyboard" : "Connect the keyboard over USB in wired mode")
                    }
                } header: {
                    Text("Keyboard")
                } footer: {
                    Text("Remaps live in the keyboard's firmware, so they work on any computer without this app. Apply as you change is off by default because remapping a modifier takes effect while you type. Holding Fn+Esc for a few seconds is the keyboard's own factory reset.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog("Reset the keyboard to its factory layout?", isPresented: $confirmingFactory) {
            Button("Reset Keyboard", role: .destructive) { model.resetKeyboardRemaps() }
        } message: {
            Text("This clears the remaps on both layers of the keyboard and in this editor.")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                PrimaryToolbarButton(title: "Apply", symbol: "checkmark.circle.fill", enabled: model.isWired && !model.busy,
                                     help: model.isWired ? "Send the \(model.remapLayer.name) to the keyboard (⌘↩)" : "Connect the keyboard over USB in wired mode") {
                    model.applyRemap(model.remapLayer)
                }
            }
        }
        .onAppear {
            // `-remap-edit capslock` opens the action picker for that key (used for screenshots).
            if editing == nil, let n = UserDefaults.standard.string(forKey: "remap-edit"), let k = RemapText.layout.key(named: n) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { editing = k }
            }
        }
    }

    private func face(_ k: KeyCap, _ map: RemapTable) -> KeyFace {
        if let a = map[k.light], let label = RemapText.short(a) {
            return KeyFace(fill: .accentColor, ink: .white, label: label)
        }
        if k.usage == nil, model.remapLayer == .fn {
            return KeyFace(ink: .accentColor)
        }
        return KeyFace()
    }
}

/// Shows a checkmark before the title of the preset that matches the Normal layer.
private struct PresetLabelStyle: LabelStyle {
    let active: Bool
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            if active { configuration.icon.font(.caption.weight(.bold)).foregroundStyle(.tint) }
            configuration.title.lineLimit(1)
        }
    }
}

private struct ChangeRow: View {
    @Environment(AppModel.self) private var model
    let key: KeyCap
    let action: KeyAction

    var body: some View {
        HStack(spacing: 10) {
            Text(RemapText.name(key))
                .frame(minWidth: 96, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(RemapText.long(action))
                .fontWeight(.medium)
            Spacer(minLength: 8)
            Button { model.setAction(nil, for: key) } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove this change")
            .accessibilityLabel("Remove")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(RemapText.name(key)) to \(RemapText.long(action))")
    }
}

// MARK: Action picker

private struct RemapOption: Identifiable {
    enum Group: String, CaseIterable {
        case keys = "Keys", modifiers = "Modifiers", media = "Media", system = "System"
    }
    let id: String
    let group: Group
    let title: String
    var detail = ""
    /// For keys, the modifier checkboxes are added when chosen.
    let action: KeyAction
    let terms: String

    static let all: [RemapOption] = {
        var out: [RemapOption] = []
        for k in RemapText.layout.keys {
            // Modifier keys are listed under Modifiers, where they act as real modifiers.
            guard let u = k.usage, !(0xE0...0xE7).contains(u) else { continue }
            let name = RemapText.name(k)
            out.append(RemapOption(id: "key-\(k.name)", group: .keys, title: name, action: .key(usage: u),
                                   terms: "\(name) \(k.name) \(k.label)"))
        }
        for right in [false, true] {
            for m in [RemapText.modifiers[0], RemapText.modifiers[2], RemapText.modifiers[1], RemapText.modifiers[3]] {
                let side = right ? "Right" : "Left"
                out.append(RemapOption(id: "mod-\(side)-\(m.mac)", group: .modifiers,
                                       title: "\(side) \(m.symbol) \(m.mac) (\(m.win))",
                                       action: .modifier(right ? m.bit << 4 : m.bit),
                                       terms: "\(side) \(m.mac) \(m.win) \(m.mac == "Command" ? "cmd" : "") \(m.mac == "Control" ? "ctrl" : "") \(m.mac == "Option" ? "opt" : "")"))
            }
        }
        let media: [KeyAction] = [.playPause, .stop, .previousTrack, .nextTrack, .volumeUp, .volumeDown, .mute]
        for a in media {
            let t = RemapText.long(a)
            out.append(RemapOption(id: "media-\(t)", group: .media, title: t, action: a, terms: t + " audio music sound"))
        }
        let system: [KeyAction] = [RemapText.capsLock, .special(0x01, 0x01), .special(0x01, 0x04), .special(0x03, 0xFF), .special(0x03, 0x01)]
        for a in system {
            let t = RemapText.long(a)
            out.append(RemapOption(id: "sys-\(t)", group: .system, title: t, action: a, terms: t + (t == "Lock PC" ? " screen sleep" : "")))
        }
        return out
    }()
}

private struct RemapPicker: View {
    @Environment(AppModel.self) private var model
    let key: KeyCap
    let close: () -> Void

    @State private var query = ""
    @State private var mods: UInt8 = 0
    @FocusState private var searchFocused: Bool

    private var current: KeyAction? { model.currentRemap[key.light] }

    private var filtered: [RemapOption] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return RemapOption.all }
        return RemapOption.all.filter { "\($0.title) \($0.terms) \($0.group.rawValue)".lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)
            if key.usage == nil {
                Text("Fn switches to the Fn layer, so it can't be remapped. Pick “Fn layer” above the keyboard to change what keys do while it is held.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .frame(width: 300, alignment: .leading)
            } else {
                picker
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(RemapText.name(key)).font(.headline)
            if key.usage != nil {
                Text("\(model.remapLayer.name) · now \(current.map(RemapText.long) ?? "default")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Search", text: $query, prompt: Text("Search keys and actions"))
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .onSubmit { if let first = filtered.first { choose(first) } }
                HStack(spacing: 10) {
                    Text("Keys with").font(.caption).foregroundStyle(.secondary)
                    modToggle("Ctrl", 0x01)
                    modToggle("Shift", 0x02)
                    modToggle("Option", 0x04)
                    modToggle("Cmd", 0x08)
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Divider()

            let options = filtered
            if options.isEmpty {
                Text("No matches")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(RemapOption.Group.allCases, id: \.self) { g in
                        let rows = options.filter { $0.group == g }
                        if !rows.isEmpty {
                            Section(g.rawValue) {
                                ForEach(rows) { row($0) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }

            Divider()

            HStack {
                Button("Disable Key") { model.setAction(.disabled, for: key); close() }
                    .disabled(current == .disabled)
                    .help("The key does nothing")
                Spacer()
                Button("Reset to Default") { model.setAction(nil, for: key); close() }
                    .disabled(current == nil)
                    .help("The key goes back to its factory action")
            }
            .padding(10)
        }
        .frame(width: 340, height: 420)
        .onAppear {
            if case .key(_, let m) = current { mods = m & 0x0F }
            searchFocused = true
        }
    }

    private func modToggle(_ title: String, _ bit: UInt8) -> some View {
        Toggle(title, isOn: Binding(get: { mods & bit != 0 }, set: { mods = $0 ? mods | bit : mods & ~bit }))
            .toggleStyle(.checkbox)
            .help("Hold \(title) along with the key you pick from Keys")
    }

    private func isCurrent(_ o: RemapOption) -> Bool {
        guard let current else {
            // Unchanged: the key's own entry is what it sends.
            if case .key(let u, 0) = o.action { return u == key.usage && mods == 0 }
            return false
        }
        if case .key(let u, _) = o.action { return current == .key(usage: u, modifiers: mods) }
        return current == o.action
    }

    private func row(_ o: RemapOption) -> some View {
        Button { choose(o) } label: {
            HStack(spacing: 8) {
                Text(o.group == .keys && mods != 0 ? RemapText.symbols(mods) + o.title : o.title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isCurrent(o) {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func choose(_ o: RemapOption) {
        var a = o.action
        if case .key(let u, _) = a { a = .key(usage: u, modifiers: mods) }
        model.setAction(a, for: key)
        close()
    }
}
