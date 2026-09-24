import AppKit
import AulaKit
import SwiftUI

// MARK: Model types

/// An 8-bit sRGB color, as the keyboard takes it.
struct RGB: Codable, Hashable, Sendable {
    var r: UInt8
    var g: UInt8
    var b: UInt8

    init(r: UInt8, g: UInt8, b: UInt8) { self.r = r; self.g = g; self.b = b }
    init(_ c: Color) { self.init(NSColor(c)) }
    init(_ ns: NSColor) {
        let c = ns.usingColorSpace(.sRGB) ?? .white
        func b(_ v: CGFloat) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }
        self.init(r: b(c.redComponent), g: b(c.greenComponent), b: b(c.blueComponent))
    }

    var color: Color { Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
    /// Relative luminance, 0...1, for picking a readable label color.
    var luminance: Double { (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255 }

    static func hsb(_ h: Double, _ s: Double = 1, _ v: Double = 1) -> RGB {
        RGB(NSColor(hue: h.truncatingRemainder(dividingBy: 1), saturation: s, brightness: v, alpha: 1))
    }

    func mix(_ o: RGB, _ t: Double) -> RGB {
        func m(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8((Double(a) + (Double(b) - Double(a)) * t).rounded()) }
        return RGB(r: m(r, o.r), g: m(g, o.g), b: m(b, o.b))
    }

    func scaled(_ f: Double) -> RGB {
        func s(_ a: UInt8) -> UInt8 { UInt8(min(255, (Double(a) * f).rounded())) }
        return RGB(r: s(r), g: s(g), b: s(b))
    }

    static let palette: [RGB] = [
        RGB(r: 255, g: 255, b: 255), RGB(r: 255, g: 40, b: 40), RGB(r: 255, g: 120, b: 0), RGB(r: 255, g: 210, b: 0),
        RGB(r: 150, g: 255, b: 0), RGB(r: 0, g: 220, b: 80), RGB(r: 0, g: 220, b: 200), RGB(r: 0, g: 170, b: 255),
        RGB(r: 30, g: 60, b: 255), RGB(r: 130, g: 40, b: 255), RGB(r: 230, g: 0, b: 255), RGB(r: 255, g: 60, b: 150),
    ]
}

/// A named per-key color map. Colors are keyed by key name so the file stays readable.
struct KeyMap: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var colors: [String: RGB]
    var brightness: UInt8
    var created = Date()

    var lights: [UInt8: RGB] {
        var out: [UInt8: RGB] = [:]
        for (n, c) in colors { if let k = KeyLayout.f108Pro.key(named: n) { out[k.light] = c } }
        return out
    }

    static func names(_ lights: [UInt8: RGB]) -> [String: RGB] {
        var out: [String: RGB] = [:]
        for k in KeyLayout.f108Pro.keys { if let c = lights[k.light] { out[k.name] = c } }
        return out
    }
}

/// What is written to KeyMaps.json next to the library folder.
private struct KeyMapFile: Codable {
    var current: [String: RGB]
    var brightness: UInt8
    var saved: [KeyMap]
}

enum KeyPreset: String, CaseIterable, Identifiable {
    case rainbow, gradient, random, wasd, typing
    var id: String { rawValue }
    var name: String {
        switch self {
        case .rainbow: "Rainbow"
        case .gradient: "Gradient"
        case .random: "Random"
        case .wasd: "WASD"
        case .typing: "Typing"
        }
    }
    var help: String {
        switch self {
        case .rainbow: "Hue runs across the keyboard from left to right"
        case .gradient: "Blend from the first color to the second, left to right"
        case .random: "A random color on every key"
        case .wasd: "WASD, arrows and space in the first color, the rest dimmed in the second"
        case .typing: "Letters in the first color, every other key in the second"
        }
    }
}

// MARK: Model logic

extension AppModel {
    var keyBrush: RGB? { keyErasing ? nil : keyBrushColor }

    private var keyMapsURL: URL? { sidecarURL("KeyMaps.json") }

    /// A settings file next to the library folder, or in Application Support without one.
    func sidecarURL(_ name: String) -> URL? {
        if let root = store?.root { return root.deletingLastPathComponent().appendingPathComponent(name) }
        return try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("AulaStudio/\(name)")
    }

    func loadKeyMaps() {
        if let url = keyMapsURL, let data = try? Data(contentsOf: url) {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            if let file = try? dec.decode(KeyMapFile.self, from: data) {
                keyColors = KeyMap(name: "", colors: file.current, brightness: file.brightness).lights
                keyBrightness = min(file.brightness, 5)
                keyMaps = file.saved
            }
        }
        keysLoaded = true
        // `-selftest-keys rainbow|wasd|gradient|random|typing` paints a preset at launch (used for screenshots).
        // With "Apply as you paint" on and the keyboard wired, it is sent like any other change.
        if let name = UserDefaults.standard.string(forKey: "selftest-keys"), let p = KeyPreset(rawValue: name.lowercased()) {
            applyKeyPreset(p)
        }
    }

    private func saveKeyMapsFile() {
        guard let url = keyMapsURL else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let file = KeyMapFile(current: KeyMap.names(keyColors), brightness: keyBrightness, saved: keyMaps)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try enc.encode(file).write(to: url, options: .atomic)
        } catch {
            show("Could not save key maps: \(error.localizedDescription)", error: true)
        }
    }

    /// Debounced: saves the working map and, with "Apply as you paint" on, sends it.
    func keysChanged() {
        guard keysLoaded else { return }
        keysTask?.cancel()
        keysTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            saveKeyMapsFile()
            guard liveKeys, isWired else { return }
            // Wait out another device operation rather than dropping the change.
            while busy {
                try? await Task.sleep(for: .milliseconds(150))
                if Task.isCancelled { return }
            }
            applyKeys(quiet: true)
        }
    }

    func applyKeys(quiet: Bool = false) {
        guard isWired else { showNotWired(); return }
        let colors = keyColors.mapValues { (r: $0.r, g: $0.g, b: $0.b) }
        let brightness = keyBrightness
        withDevice("Key colors set", quiet: quiet) { try $0.setPerKeyColors(colors, brightness: brightness) }
    }

    private func setKey(_ light: UInt8, _ c: RGB?) {
        if keyColors[light] != c { keyColors[light] = c }
    }

    func pressKey(_ key: KeyCap, double: Bool, option: Bool) {
        if option {
            if let c = keyColors[key.light] { keyBrushColor = c; keyErasing = false } else { keyErasing = true }
            return
        }
        // The first click of a double-click painted the key; the second turns it off.
        if double { setKey(key.light, nil); return }
        setKey(key.light, keyBrush)
    }

    func dragKey(_ key: KeyCap) { setKey(key.light, keyBrush) }

    func fillAllKeys() {
        guard let c = keyBrush else { keyColors = [:]; return }
        keyColors = Dictionary(uniqueKeysWithValues: KeyLayout.f108Pro.keys.map { ($0.light, c) })
    }

    func applyKeyPreset(_ p: KeyPreset) {
        let layout = KeyLayout.f108Pro
        func center(_ k: KeyCap) -> Double { (k.x + k.width / 2) / layout.widthUnits }
        var out: [UInt8: RGB] = [:]
        for k in layout.keys {
            switch p {
            case .rainbow:
                out[k.light] = .hsb(center(k) * 0.92)
            case .gradient:
                out[k.light] = keyPrimary.mix(keySecondary, center(k))
            case .random:
                out[k.light] = .hsb(Double.random(in: 0..<1), Double.random(in: 0.75...1))
            case .wasd:
                let accent: Set = ["w", "a", "s", "d", "up", "down", "left", "right", "space"]
                out[k.light] = accent.contains(k.name) ? keyPrimary : keySecondary.scaled(0.22)
            case .typing:
                let letter = k.name.count == 1 && k.name.first!.isLetter
                out[k.light] = letter ? keyPrimary : keySecondary
            }
        }
        keyColors = out
    }

    func saveKeyMap(named raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let colors = KeyMap.names(keyColors)
        if let i = keyMaps.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            keyMaps[i].colors = colors
            keyMaps[i].brightness = keyBrightness
            show("Updated “\(keyMaps[i].name)”")
        } else {
            keyMaps.append(KeyMap(name: name, colors: colors, brightness: keyBrightness))
            show("Saved “\(name)”")
        }
        saveKeyMapsFile()
    }

    func loadKeyMap(_ map: KeyMap) {
        keyColors = map.lights
        keyBrightness = min(map.brightness, 5)
    }

    func renameKeyMap(_ map: KeyMap, to raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let i = keyMaps.firstIndex(where: { $0.id == map.id }) else { return }
        keyMaps[i].name = name
        saveKeyMapsFile()
    }

    func deleteKeyMap(_ map: KeyMap) {
        keyMaps.removeAll { $0.id == map.id }
        saveKeyMapsFile()
    }
}

// MARK: Page

struct KeysView: View {
    @Environment(AppModel.self) private var model
    @State private var saveName = ""
    @State private var deleting: KeyMap?
    @State private var renaming: UUID?

    var body: some View {
        @Bindable var model = model
        Page {
            WiredNotice(message: "Key colors are set over USB. You can still paint and save maps without it.")

            VStack(alignment: .leading, spacing: 12) {
                KeyboardCanvas(colors: model.keyColors,
                               onPress: { model.pressKey($0, double: $1, option: $2) },
                               onDrag: { model.dragKey($0) })
                brushBar
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Click or drag to paint. Option-click picks up a key's color. Double-click turns a key off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Fill All") { model.fillAllKeys() }
                        .help("Paint every key with the current color")
                    Button("Clear All") { model.keyColors = [:] }
                        .help("Turn every key off")
                }
                .controlSize(.small)
            }

            EmbeddedForm {
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: KeyPreset.allCases.count), spacing: 8) {
                        ForEach(KeyPreset.allCases) { p in
                            Button { model.applyKeyPreset(p) } label: {
                                Text(p.name).frame(maxWidth: .infinity)
                            }
                            .help(p.help)
                        }
                    }
                    .padding(.vertical, 2)
                    LabeledContent("Colors") {
                        HStack(spacing: 8) {
                            ColorPicker("First", selection: rgbBinding(\.keyPrimary), supportsOpacity: false).labelsHidden()
                            Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                            ColorPicker("Second", selection: rgbBinding(\.keySecondary), supportsOpacity: false).labelsHidden()
                        }
                    }
                } header: {
                    Text("Presets")
                } footer: {
                    Text("Gradient blends the first color into the second. WASD and Typing use the first for highlights and the second for the rest.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("Brightness") {
                        HStack(spacing: 8) {
                            Slider(value: Binding(get: { Double(model.keyBrightness) },
                                                  set: { model.keyBrightness = UInt8($0.rounded()) }),
                                   in: 0...5, step: 1)
                            Text("\(model.keyBrightness)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 16, alignment: .trailing)
                        }
                    }
                    Toggle("Apply as you paint", isOn: $model.liveKeys)
                } header: {
                    Text("Keyboard")
                } footer: {
                    Text("Per-key colors are a static effect. Choosing an effect on the Lighting page replaces them.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack(spacing: 8) {
                        TextField("Save as", text: $saveName, prompt: Text("Name"))
                            .onSubmit(save)
                        Button("Save", action: save)
                            .disabled(saveName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if model.keyMaps.isEmpty {
                        Text("No saved maps yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.keyMaps) { map in
                            KeyMapRow(map: map, renaming: $renaming) { deleting = map }
                        }
                    }
                } header: {
                    Text("Saved Maps")
                } footer: {
                    Text("Saving under an existing name replaces that map.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let d = deleting { model.deleteKeyMap(d) }
                deleting = nil
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                PrimaryToolbarButton(title: "Apply", symbol: "checkmark.circle.fill", enabled: model.isWired && !model.busy,
                                     help: model.isWired ? "Set these key colors on the keyboard (⌘↩)" : "Connect the keyboard over USB in wired mode") {
                    model.applyKeys()
                }
            }
        }
    }

    private var brushBar: some View {
        HStack(spacing: 10) {
            ColorPicker("Color", selection: Binding(get: { model.keyBrushColor.color },
                                                    set: { model.keyBrushColor = RGB($0); model.keyErasing = false }),
                        supportsOpacity: false)
                .labelsHidden()
                .help("Current color")
            Divider().frame(height: 20)
            ViewThatFits(in: .horizontal) {
                swatches(size: 22)
                swatches(size: 18)
            }
            Spacer(minLength: 0)
        }
    }

    private func swatches(size: CGFloat) -> some View {
        HStack(spacing: size < 20 ? 5 : 7) {
            ForEach(RGB.palette, id: \.self) { c in
                Swatch(fill: c.color, selected: !model.keyErasing && model.keyBrushColor == c, size: size) {
                    model.keyBrushColor = c
                    model.keyErasing = false
                }
                .help("Paint with this color")
            }
            Swatch(fill: nil, selected: model.keyErasing, size: size) { model.keyErasing = true }
                .help("Paint keys off")
        }
    }

    private func rgbBinding(_ kp: ReferenceWritableKeyPath<AppModel, RGB>) -> Binding<Color> {
        Binding(get: { model[keyPath: kp].color }, set: { model[keyPath: kp] = RGB($0) })
    }

    private func save() {
        model.saveKeyMap(named: saveName)
        saveName = ""
    }
}

private struct Swatch: View {
    /// nil draws the "Off" swatch.
    let fill: Color?
    let selected: Bool
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if let fill {
                    Circle().fill(fill)
                } else {
                    Circle().fill(Color(white: 0.2))
                    Image(systemName: "slash.circle").font(.system(size: size * 0.6, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
            }
            .frame(width: size, height: size)
            .padding(3)
            .overlay(Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(fill == nil ? "Off" : "Color")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct KeyMapRow: View {
    @Environment(AppModel.self) private var model
    let map: KeyMap
    @Binding var renaming: UUID?
    let delete: () -> Void
    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            KeyboardCanvas(colors: map.lights, compact: true)
                .frame(width: 104)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if renaming == map.id {
                    TextField("Name", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .focused($nameFocused)
                        .onSubmit(commit)
                        .onExitCommand { renaming = nil }
                        .onChange(of: nameFocused) { _, f in if !f { commit() } }
                } else {
                    Text(map.name).lineLimit(1).truncationMode(.tail).help(map.name)
                        .onTapGesture(count: 2) { startRename() }
                }
                Text("\(map.colors.count) keys lit · brightness \(map.brightness)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Load") { model.loadKeyMap(map) }
                .help("Load this map into the editor")
            Menu {
                Button("Rename") { startRename() }
                Button("Delete…", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
        }
        .contextMenu {
            Button("Load") { model.loadKeyMap(map) }
            Button("Rename") { startRename() }
            Divider()
            Button("Delete…", role: .destructive, action: delete)
        }
    }

    private func startRename() {
        draft = map.name
        renaming = map.id
        DispatchQueue.main.async { nameFocused = true }
    }

    private func commit() {
        guard renaming == map.id else { return }
        model.renameKeyMap(map, to: draft)
        renaming = nil
    }
}

// MARK: Canvas

/// How one key is drawn. The default is an unlit cap with its printed label.
struct KeyFace {
    /// Cap color. nil draws an unlit cap.
    var fill: Color?
    /// Rim around the cap face. Defaults to a darkened `fill`.
    var rim: Color?
    /// Label color. Defaults to a dim white on unlit caps.
    var ink: Color?
    /// Replaces the printed label.
    var label: String?

    static func lit(_ c: RGB) -> KeyFace {
        KeyFace(fill: c.color, rim: c.scaled(0.62).color,
                ink: c.luminance > 0.55 ? .black.opacity(0.72) : .white.opacity(0.92))
    }
}

/// The F108 Pro drawn from `KeyLayout.f108Pro`, scaled to the available width.
/// The board is always dark, like the physical one. Each key's look comes from `face`.
struct KeyboardCanvas: View {
    let face: (KeyCap) -> KeyFace
    var compact = false
    /// Key drawn with a selection ring.
    var selected: UInt8?
    let summary: String
    var onPress: ((KeyCap, _ double: Bool, _ option: Bool) -> Void)?
    var onDrag: ((KeyCap) -> Void)?
    /// Called on release over the key that was pressed.
    var onTap: ((KeyCap) -> Void)?

    @State private var hovered: UInt8?
    @State private var pressing = false
    @State private var sampling = false
    @State private var pressedKey: UInt8?
    @State private var lastPress: (light: UInt8, time: Date)?

    /// Per-key colors, as the Keys page paints them.
    init(colors: [UInt8: RGB], compact: Bool = false,
         onPress: ((KeyCap, _ double: Bool, _ option: Bool) -> Void)? = nil, onDrag: ((KeyCap) -> Void)? = nil) {
        face = { colors[$0.light].map(KeyFace.lit) ?? KeyFace() }
        self.compact = compact
        summary = "\(colors.count) of \(Self.layout.keys.count) keys lit"
        self.onPress = onPress
        self.onDrag = onDrag
    }

    init(summary: String, selected: UInt8? = nil, face: @escaping (KeyCap) -> KeyFace, onTap: ((KeyCap) -> Void)? = nil) {
        self.face = face
        self.summary = summary
        self.selected = selected
        self.onTap = onTap
    }

    private static let layout = KeyLayout.f108Pro
    /// Board margin around the keys, in key units.
    private static let pad = 0.45
    /// Extra room above the function row for the screen and knob.
    private static let top = 0.8
    private static var totalW: Double { layout.widthUnits + pad * 2 }
    private static var totalH: Double { layout.heightUnits + top + pad * 2 }

    /// Where a key sits in a canvas of the given width, for anchoring popovers.
    static func frame(of k: KeyCap, width: Double) -> CGRect {
        let unit = width / totalW
        return CGRect(x: (pad + k.x) * unit, y: (pad + top + k.y) * unit, width: k.width * unit, height: k.height * unit)
    }

    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.width / Self.totalW
            Canvas { ctx, _ in draw(&ctx, unit: unit) }
                .contentShape(Rectangle())
                .gesture(drag(unit: unit), including: compact ? .none : .all)
                .onContinuousHover { phase in
                    guard !compact else { return }
                    switch phase {
                    case .active(let p): hovered = key(at: p, unit: unit)?.light
                    case .ended: hovered = nil
                    }
                }
        }
        .aspectRatio(Self.totalW / Self.totalH, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Keyboard")
        .accessibilityValue(summary)
    }

    // MARK: Hit testing

    private func key(at p: CGPoint, unit: Double) -> KeyCap? {
        let ux = p.x / unit - Self.pad, uy = p.y / unit - Self.pad - Self.top
        return Self.layout.keys.first { ux >= $0.x && ux < $0.x + $0.width && uy >= $0.y && uy < $0.y + $0.height }
    }

    private func drag(unit: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let k = key(at: v.location, unit: unit)
                if !pressing {
                    pressing = true
                    pressedKey = k?.light
                    sampling = NSEvent.modifierFlags.contains(.option)
                    guard let k else { return }
                    let now = Date()
                    let double = lastPress.map { $0.light == k.light && now.timeIntervalSince($0.time) < NSEvent.doubleClickInterval } ?? false
                    lastPress = double ? nil : (k.light, now)
                    onPress?(k, double, sampling)
                    return
                }
                if !sampling, let k { onDrag?(k) }
                hovered = k?.light
            }
            .onEnded { v in
                if let onTap, let k = key(at: v.location, unit: unit), k.light == pressedKey { onTap(k) }
                pressing = false
                sampling = false
                pressedKey = nil
            }
    }

    // MARK: Drawing

    private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, unit: Double) -> CGRect {
        CGRect(x: (Self.pad + x) * unit, y: (Self.pad + Self.top + y) * unit, width: w * unit, height: h * unit)
    }

    private func draw(_ ctx: inout GraphicsContext, unit: Double) {
        let board = CGRect(x: 0, y: 0, width: Self.totalW * unit, height: Self.totalH * unit)
        let boardPath = Path(roundedRect: board, cornerRadius: (compact ? 0.5 : 0.35) * unit, style: .continuous)
        ctx.fill(boardPath, with: .linearGradient(Gradient(colors: [Color(white: 0.2), Color(white: 0.11)]),
                                                  startPoint: .zero, endPoint: CGPoint(x: 0, y: board.height)))
        ctx.stroke(boardPath, with: .color(.white.opacity(0.1)), lineWidth: 1)

        drawScreenBlock(&ctx, unit: unit)

        let inset = 0.05
        func capRect(_ k: KeyCap) -> CGRect {
            rect(k.x + inset, k.y + inset, k.width - inset * 2, k.height - inset * 2, unit: unit)
        }
        let faces = Self.layout.keys.map { ($0, face($0)) }

        // Underglow for lit keys, blurred once as a layer.
        if !compact, faces.contains(where: { $0.1.fill != nil }) {
            ctx.drawLayer { glow in
                glow.addFilter(.blur(radius: unit * 0.22))
                glow.opacity = 0.55
                for (k, f) in faces {
                    guard let c = f.fill else { continue }
                    glow.fill(Path(roundedRect: capRect(k), cornerRadius: unit * 0.14), with: .color(c))
                }
            }
        }

        let radius = unit * 0.13
        for (k, f) in faces {
            let r = capRect(k)
            let outer = Path(roundedRect: r, cornerRadius: radius, style: .continuous)
            let face = CGRect(x: r.minX + unit * 0.07, y: r.minY + unit * 0.04,
                              width: r.width - unit * 0.14, height: r.height - unit * 0.15)
            let facePath = Path(roundedRect: face, cornerRadius: radius * 0.8, style: .continuous)
            if let c = f.fill {
                if let rim = f.rim {
                    ctx.fill(outer, with: .color(rim))
                } else {
                    ctx.fill(outer, with: .color(Color(white: 0.06)))
                    ctx.fill(outer, with: .color(c.opacity(0.62)))
                }
                ctx.fill(facePath, with: .color(c))
                ctx.fill(facePath, with: .linearGradient(Gradient(colors: [.white.opacity(0.18), .clear]),
                                                         startPoint: CGPoint(x: 0, y: face.minY), endPoint: CGPoint(x: 0, y: face.midY)))
            } else {
                ctx.fill(outer, with: .color(Color(white: 0.12)))
                ctx.fill(facePath, with: .linearGradient(Gradient(colors: [Color(white: 0.25), Color(white: 0.19)]),
                                                         startPoint: CGPoint(x: 0, y: face.minY), endPoint: CGPoint(x: 0, y: face.maxY)))
            }
            if selected == k.light {
                let ring = Path(roundedRect: r.insetBy(dx: -unit * 0.03, dy: -unit * 0.03), cornerRadius: radius * 1.2, style: .continuous)
                ctx.stroke(ring, with: .color(.white), lineWidth: 2)
            } else if hovered == k.light {
                ctx.stroke(outer, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
            }

            let label = f.label ?? k.label
            guard !compact, !label.isEmpty else { continue }
            let ink = f.ink ?? (f.fill == nil ? .white.opacity(0.55) : .white.opacity(0.92))
            var size = unit * 0.3
            var text = ctx.resolve(Text(label).font(.system(size: size, weight: .medium)).foregroundColor(ink))
            let avail = face.width - unit * 0.1
            let w = text.measure(in: CGSize(width: 1000, height: 1000)).width
            if w > avail {
                size *= avail / w
                text = ctx.resolve(Text(label).font(.system(size: size, weight: .medium)).foregroundColor(ink))
            }
            ctx.draw(text, at: CGPoint(x: face.midX, y: face.midY), anchor: .center)
        }
    }

    /// The 240x135 screen and the knob, above the numpad. Not interactive.
    private func drawScreenBlock(_ ctx: inout GraphicsContext, unit: Double) {
        let bezel = rect(18.5, -0.72, 2.95, 1.68, unit: unit)
        ctx.fill(Path(roundedRect: bezel, cornerRadius: unit * 0.12, style: .continuous), with: .color(.black))
        let screen = bezel.insetBy(dx: unit * 0.07, dy: unit * 0.07)
        ctx.fill(Path(roundedRect: screen, cornerRadius: unit * 0.04),
                 with: .linearGradient(Gradient(colors: [Color(red: 0.06, green: 0.08, blue: 0.14), Color(white: 0.03)]),
                                       startPoint: CGPoint(x: screen.minX, y: screen.minY), endPoint: CGPoint(x: screen.maxX, y: screen.maxY)))
        ctx.stroke(Path(roundedRect: bezel, cornerRadius: unit * 0.12, style: .continuous), with: .color(.white.opacity(0.08)), lineWidth: 1)
        if !compact {
            let t = ctx.resolve(Text("12:34").font(.system(size: unit * 0.46, weight: .light, design: .rounded))
                .foregroundColor(.white.opacity(0.35)))
            ctx.draw(t, at: CGPoint(x: screen.midX, y: screen.midY), anchor: .center)
        }

        let knob = rect(21.62, -0.34, 0.84, 0.84, unit: unit)
        ctx.drawLayer { k in
            if !compact { k.addFilter(.shadow(color: .black.opacity(0.5), radius: unit * 0.08, y: unit * 0.05)) }
            k.fill(Path(ellipseIn: knob), with: .linearGradient(Gradient(colors: [Color(white: 0.42), Color(white: 0.16)]),
                                                                 startPoint: CGPoint(x: knob.minX, y: knob.minY),
                                                                 endPoint: CGPoint(x: knob.maxX, y: knob.maxY)))
        }
        let inner = knob.insetBy(dx: knob.width * 0.12, dy: knob.width * 0.12)
        ctx.fill(Path(ellipseIn: inner), with: .radialGradient(Gradient(colors: [Color(white: 0.32), Color(white: 0.2)]),
                                                               center: CGPoint(x: inner.minX, y: inner.minY),
                                                               startRadius: 0, endRadius: inner.width))
        if !compact {
            let tick = CGRect(x: knob.midX - unit * 0.025, y: knob.minY + unit * 0.12, width: unit * 0.05, height: unit * 0.17)
            ctx.fill(Path(roundedRect: tick, cornerRadius: unit * 0.025), with: .color(.white.opacity(0.5)))
            // Status LEDs under the knob.
            for i in 0..<3 {
                let d = unit * 0.09
                let led = CGRect(x: knob.minX + knob.width * (0.2 + Double(i) * 0.3) - d / 2, y: knob.maxY + unit * 0.14, width: d, height: d)
                ctx.fill(Path(ellipseIn: led), with: .color(i == 0 ? Color.green.opacity(0.8) : .white.opacity(0.14)))
            }
        }
    }
}
