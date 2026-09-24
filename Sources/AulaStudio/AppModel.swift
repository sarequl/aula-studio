import AppKit
import AulaKit
import Foundation
import Observation
import SwiftUI

/// Sidebar destinations. (Not called `Section` so SwiftUI's `Section` stays usable.)
enum Pane: String, CaseIterable, Identifiable {
    case screen, library, text, lighting, clock
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .screen: "photo.on.rectangle.angled"
        case .library: "square.stack"
        case .text: "textformat"
        case .lighting: "light.max"
        case .clock: "clock"
        }
    }
    var shortcut: KeyEquivalent {
        KeyEquivalent(Character(String((Pane.allCases.firstIndex(of: self) ?? 0) + 1)))
    }
}

/// Built-in solid colors shown next to the gradient presets.
struct SolidPreset: Identifiable {
    let name: String
    let rgb: [UInt8]
    var id: String { name }
    var color: Color { Color(.sRGB, red: Double(rgb[0]) / 255, green: Double(rgb[1]) / 255, blue: Double(rgb[2]) / 255) }

    static let all = [
        SolidPreset(name: "Black", rgb: [0, 0, 0]),
        SolidPreset(name: "White", rgb: [255, 255, 255]),
        SolidPreset(name: "Red", rgb: [255, 45, 45]),
        SolidPreset(name: "Blue", rgb: [30, 100, 255]),
    ]
}

/// Curated fonts for the Text section, by PostScript name.
enum TextFonts {
    static let all: [(name: String, label: String)] = [
        ("Helvetica-Bold", "Helvetica Bold"),
        ("HelveticaNeue-Light", "Helvetica Neue Light"),
        ("Avenir-Black", "Avenir Black"),
        ("Futura-Bold", "Futura Bold"),
        ("Georgia-Bold", "Georgia Bold"),
        ("Impact", "Impact"),
        ("Menlo-Bold", "Menlo Bold"),
        ("Courier-Bold", "Courier Bold"),
        ("ChalkboardSE-Bold", "Chalkboard Bold"),
        ("MarkerFelt-Wide", "Marker Felt Wide"),
    ]
}

/// SwiftUI also declares a `LibraryItem` (for the Xcode library), so name ours explicitly.
typealias SavedItem = AulaKit.LibraryItem

struct StudioError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case lastSent, added
    var id: String { rawValue }
    var label: String { self == .lastSent ? "Last Sent" : "Date Added" }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    // Navigation
    var pane: Pane = Pane(rawValue: (UserDefaults.standard.string(forKey: "tab") ?? "").lowercased()) ?? .screen
    var importing = false

    // Connection
    var connection: ConnectionState = .absent
    /// Detected model, or the default when nothing is plugged in.
    var profile: KeyboardProfile = .f108Pro
    var busy = false
    var toast: Toast?

    // Screen
    var sourceURL: URL?
    /// Display name for the loaded media (library name or file name).
    var sourceName: String?
    var source: SourceMedia?
    var rendered: LCDImage?
    var scaleMode: ScaleMode = .fill { didSet { rerender() } }
    var playbackSpeed: Double = 1.0 { didSet { rerender() } }
    var videoFPS: Double = 15
    var loading = false
    /// Library item the Screen section was loaded from, if any.
    var screenItemID: UUID?

    // Upload
    var uploadProgress: Double?
    var uploadStarted: Date?
    var uploadName = ""
    var uploading: Bool { uploadProgress != nil }

    // Text
    var text = "Hello" { didSet { scheduleTextRender() } }
    var fontName = "Helvetica-Bold" { didSet { scheduleTextRender() } }
    var fontSize: Double = 56 { didSet { scheduleTextRender() } }
    var textColor: Color = .white { didSet { scheduleTextRender() } }
    var textBackground: Color = .black { didSet { scheduleTextRender() } }
    var scrolling = false { didSet { scheduleTextRender() } }
    var scrollSpeed: Double = 120 { didSet { scheduleTextRender() } }
    var textRendered: LCDImage?

    // Library
    let store: LibraryStore?
    var library: [SavedItem] = []
    var thumbnails: [UUID: NSImage] = [:]
    var presetImages: [String: LCDImage] = [:]
    /// Item being re-rendered before its upload starts.
    var preparingItemID: UUID?

    // Lighting
    var lighting = LightingConfig(mode: .spectrum, red: 0, green: 200, blue: 255, brightness: 4, speed: 3)
    var liveLighting = true

    // Clock
    var lastClockSync: Date?

    private let deviceQueue = DispatchQueue(label: "aula.device")
    private var pollTimer: Timer?
    private var renderTask: Task<Void, Never>?
    private var textTask: Task<Void, Never>?
    private var lightingDebounce: Task<Void, Never>?
    private var pendingSelfTest = false

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    private static var defaults: UserDefaults { .standard }
    var autoSyncClock: Bool { Self.defaults.object(forKey: "autoSyncClock") as? Bool ?? true }
    var defaultScaleMode: ScaleMode { ScaleMode(rawValue: Self.defaults.string(forKey: "defaultScaleMode") ?? "") ?? .fill }
    var defaultVideoFPS: Double {
        let v = Self.defaults.double(forKey: "defaultVideoFPS")
        return v >= 4 && v <= 30 ? v : 15
    }

    private init() {
        // `-library-dir <path>` keeps test runs out of the real library.
        let dir = Self.defaults.string(forKey: "library-dir").map { URL(fileURLWithPath: $0, isDirectory: true) }
        store = try? LibraryStore(directory: dir)
        library = store?.load() ?? []
        for item in library { loadThumbnail(item) }

        scaleMode = defaultScaleMode
        videoFPS = defaultVideoFPS
        refreshConnection()
        scheduleTextRender(debounce: false)

        pendingSelfTest = Self.defaults.bool(forKey: "selftest-library")
        // `AulaStudio -open file.gif` loads that file at launch. (A bare path argument would be
        // swallowed by AppKit as an open-file event and suppress the main window.)
        if let path = Self.defaults.string(forKey: "open"), FileManager.default.fileExists(atPath: path) {
            open(URL(fileURLWithPath: path))
        }
        // `-preview-upload YES` shows the upload banner without a keyboard (used for screenshots).
        if Self.defaults.bool(forKey: "preview-upload") {
            uploadName = "t300.gif"
            uploadStarted = Date().addingTimeInterval(-65)
            uploadProgress = 0.42
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshConnection() }
        }
    }

    var isWired: Bool { connection == .wired }
    var isVideo: Bool {
        guard let ext = sourceURL?.pathExtension.lowercased() else { return false }
        return ["mp4", "mov", "m4v"].contains(ext)
    }

    func refreshConnection() {
        let old = connection
        let detected = detectKeyboard()
        connection = detected?.1 ?? .absent
        // `-simulate-connection absent|wireless` previews those states (used for screenshots).
        switch Self.defaults.string(forKey: "simulate-connection") {
        case "absent": connection = .absent
        case "wireless": connection = .wireless
        default: break
        }
        if let p = detected?.0, p != profile { profile = p; rerender() }
        if old != .wired, connection == .wired, autoSyncClock, !busy {
            syncClock(quiet: true)
        }
    }

    func show(_ text: String, error: Bool = false) {
        let t = Toast(text: text, isError: error)
        withAnimation(.snappy) { toast = t }
        Task {
            try? await Task.sleep(for: .seconds(error ? 6 : 3))
            if toast == t { withAnimation(.snappy) { toast = nil } }
        }
    }

    private func showNotWired() {
        show((connection == .wireless ? AulaError.wirelessOnly : AulaError.notFound).localizedDescription, error: true)
    }

    /// Runs a device operation on the serial device queue.
    private func withDevice(_ label: String, quiet: Bool = false, onSuccess: (() -> Void)? = nil,
                            _ work: @escaping (AulaDevice) throws -> Void) {
        busy = true
        deviceQueue.async {
            let result: Result<Void, Error> = Result { try work(try AulaDevice()) }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success:
                    onSuccess?()
                    if !quiet { self.show(label) }
                case .failure(let e): self.show(e.localizedDescription, error: true)
                }
            }
        }
    }

    // MARK: Clock

    func syncClock(quiet: Bool = false) {
        withDevice("Clock synced", quiet: quiet, onSuccess: { self.lastClockSync = Date() }) { try $0.syncClock() }
    }

    // MARK: Lighting

    func applyLighting() {
        let cfg = lighting
        withDevice("Lighting set to \(cfg.mode.name)") { try $0.setLighting(cfg) }
    }

    func lightingChanged() {
        guard liveLighting, isWired else { return }
        lightingDebounce?.cancel()
        lightingDebounce = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, !busy else { return }
            let cfg = lighting
            withDevice("", quiet: true) { try $0.setLighting(cfg) }
        }
    }

    // MARK: Screen

    /// Opens a file picked or dropped by the user, with the default settings.
    func open(_ url: URL) {
        source = nil
        screenItemID = nil
        scaleMode = defaultScaleMode
        videoFPS = defaultVideoFPS
        load(url, name: url.lastPathComponent)
    }

    private func load(_ url: URL, name: String) {
        let scoped = url.startAccessingSecurityScopedResource()
        loading = true
        sourceURL = url
        sourceName = name
        let fps = videoFPS
        let maxFrames = profile.maxFrames
        Task {
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let media = try await MediaLoader.load(url, videoFPS: fps, maxFrames: maxFrames)
                source = media
                rerender()
            } catch {
                loading = false
                show(error.localizedDescription, error: true)
            }
        }
    }

    func reloadVideo() {
        if let url = sourceURL, isVideo { load(url, name: sourceName ?? url.lastPathComponent) }
    }

    func rerender() {
        guard let media = source else { return }
        let mode = scaleMode, speed = playbackSpeed, profile = profile
        renderTask?.cancel()
        loading = true
        renderTask = Task.detached(priority: .userInitiated) {
            let result = Result { try LCDImage.render(media, mode: mode, speed: speed, profile: profile) }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.loading = false
                switch result {
                case .success(let img):
                    self.rendered = img
                    self.runSelfTestIfNeeded()
                case .failure(let e): self.show(e.localizedDescription, error: true)
                }
            }
        }
    }

    func sendScreen() {
        guard let img = rendered else { return }
        send(img, name: sourceName ?? "Screen", itemID: screenItemID)
    }

    // MARK: Upload

    /// Encodes and uploads on the device queue. Progress drives the upload banner.
    func send(_ img: LCDImage, name: String, itemID: UUID? = nil) {
        guard !busy else { return }
        guard isWired else { showNotWired(); return }
        uploadName = name
        uploadProgress = 0
        uploadStarted = Date()
        withDevice("Sent. The keyboard is saving it now; wait for its progress bar to finish before unplugging.",
                   onSuccess: { self.markSent(itemID) }) { dev in
            defer { DispatchQueue.main.async { self.uploadProgress = nil; self.uploadStarted = nil } }
            let data = try img.encode()
            try dev.uploadScreen(data) { sent, total in
                DispatchQueue.main.async { self.uploadProgress = Double(sent) / Double(total) }
            }
        }
    }

    // MARK: Text

    var flattenedText: String {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    func textStyle(forceStatic: Bool = false) -> Generators.TextStyle {
        Generators.TextStyle(text: flattenedText, fontName: fontName, fontSize: CGFloat(fontSize),
                             color: Self.rgb(textColor), background: Self.rgb(textBackground),
                             scrollSpeed: scrolling && !forceStatic ? scrollSpeed : 0)
    }

    func scheduleTextRender(debounce: Bool = true) {
        let style = textStyle()
        let profile = profile
        textTask?.cancel()
        textTask = Task {
            if debounce { try? await Task.sleep(for: .milliseconds(150)) }
            guard !Task.isCancelled else { return }
            let img = await Task.detached(priority: .userInitiated) { Generators.text(style, profile: profile) }.value
            guard !Task.isCancelled else { return }
            textRendered = img
        }
    }

    func sendText() {
        guard !flattenedText.isEmpty else { return }
        // Render fresh so a pending debounce can't send a stale frame set.
        send(Generators.text(textStyle(), profile: profile), name: flattenedText)
    }

    static func rgb(_ c: Color) -> (UInt8, UInt8, UInt8) {
        guard let ns = NSColor(c).usingColorSpace(.sRGB) else { return (255, 255, 255) }
        func b(_ v: CGFloat) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }
        return (b(ns.redComponent), b(ns.greenComponent), b(ns.blueComponent))
    }

    static func color(_ c: [UInt8]?, default d: Color) -> Color {
        guard let c, c.count == 3 else { return d }
        return Color(.sRGB, red: Double(c[0]) / 255, green: Double(c[1]) / 255, blue: Double(c[2]) / 255)
    }

    // MARK: Library

    func sortedLibrary(_ sort: LibrarySort) -> [SavedItem] {
        library.sorted { a, b in
            if sort == .lastSent, a.lastSent != b.lastSent {
                return (a.lastSent ?? .distantPast) > (b.lastSent ?? .distantPast)
            }
            return a.added > b.added
        }
    }

    private func loadThumbnail(_ item: SavedItem) {
        guard let store else { return }
        thumbnails[item.id] = NSImage(contentsOf: store.thumbnailURL(item))
    }

    private func saveLibrary() {
        guard let store else { return }
        do { try store.save(library) } catch { show("Could not save the library: \(error.localizedDescription)", error: true) }
    }

    private func requireStore() -> LibraryStore? {
        if store == nil { show("The library folder in Application Support could not be created.", error: true) }
        return store
    }

    func saveScreenToLibrary() {
        guard let store = requireStore(), let url = sourceURL, let img = rendered, let first = img.frames.first else { return }

        // Loaded from the library: update that item's settings instead of adding a copy.
        if let id = screenItemID, let i = library.firstIndex(where: { $0.id == id }), store.mediaURL(library[i]) == url {
            var item = library[i]
            item.scaleMode = scaleMode.rawValue
            item.speed = playbackSpeed
            item.videoFPS = isVideo ? videoFPS : nil
            item.frameCount = img.frames.count
            item.duration = img.totalDuration
            do {
                try store.store(&item, sourceFile: nil, thumbnail: first)
                library[i] = item
                loadThumbnail(item)
                saveLibrary()
                show("Updated “\(item.name)” in the library")
            } catch { show(error.localizedDescription, error: true) }
            return
        }

        var item = SavedItem(name: url.deletingPathExtension().lastPathComponent, kind: .media,
                               frameCount: img.frames.count, duration: img.totalDuration)
        item.scaleMode = scaleMode.rawValue
        item.speed = playbackSpeed
        item.videoFPS = isVideo ? videoFPS : nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try store.store(&item, sourceFile: url, thumbnail: first)
            library.append(item)
            loadThumbnail(item)
            saveLibrary()
            screenItemID = item.id
            if let m = store.mediaURL(item) { sourceURL = m }
            sourceName = item.name
            show("Saved “\(item.name)” to the library")
        } catch { show(error.localizedDescription, error: true) }
    }

    func saveTextToLibrary() {
        guard let store = requireStore(), !flattenedText.isEmpty else { return }
        let full = Generators.text(textStyle(), profile: profile)
        // A marquee's first frame is empty, so the thumbnail uses the static layout.
        let thumb = Generators.text(textStyle(forceStatic: true), profile: profile)
        let name = flattenedText.count > 40 ? String(flattenedText.prefix(40)) + "…" : flattenedText
        var item = SavedItem(name: name, kind: .text, frameCount: full.frames.count, duration: full.totalDuration)
        item.text = flattenedText
        item.fontName = fontName
        item.fontSize = fontSize
        item.scrollSpeed = scrolling ? scrollSpeed : 0
        let fg = Self.rgb(textColor), bg = Self.rgb(textBackground)
        item.color = [fg.0, fg.1, fg.2]
        item.background = [bg.0, bg.1, bg.2]
        do {
            try store.store(&item, sourceFile: nil, thumbnail: thumb.frames[0])
            library.append(item)
            loadThumbnail(item)
            saveLibrary()
            show("Saved “\(item.name)” to the library")
        } catch { show(error.localizedDescription, error: true) }
    }

    func rename(_ item: SavedItem, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = library.firstIndex(where: { $0.id == item.id }) else { return }
        library[i].name = trimmed
        if screenItemID == item.id { sourceName = trimmed }
        saveLibrary()
    }

    func delete(_ item: SavedItem) {
        store?.remove(item)
        library.removeAll { $0.id == item.id }
        thumbnails[item.id] = nil
        if screenItemID == item.id { screenItemID = nil }
        saveLibrary()
    }

    private func markSent(_ id: UUID?) {
        guard let id, let i = library.firstIndex(where: { $0.id == id }) else { return }
        library[i].lastSent = Date()
        saveLibrary()
    }

    func loadIntoScreen(_ item: SavedItem) {
        guard item.kind == .media, let url = store?.mediaURL(item) else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            show("The saved file for “\(item.name)” is missing.", error: true)
            return
        }
        source = nil  // so the setters below don't re-render the old media
        scaleMode = ScaleMode(rawValue: item.scaleMode ?? "") ?? .fill
        playbackSpeed = item.speed ?? 1
        videoFPS = item.videoFPS ?? defaultVideoFPS
        screenItemID = item.id
        load(url, name: item.name)
        pane = .screen
    }

    func loadIntoText(_ item: SavedItem) {
        guard item.kind == .text else { return }
        text = item.text ?? ""
        fontName = item.fontName ?? "Helvetica-Bold"
        fontSize = item.fontSize ?? 56
        textColor = Self.color(item.color, default: .white)
        textBackground = Self.color(item.background, default: .black)
        scrolling = (item.scrollSpeed ?? 0) > 0
        if scrolling { scrollSpeed = item.scrollSpeed ?? 120 }
        pane = .text
    }

    func sendItem(_ item: SavedItem) {
        guard !busy, preparingItemID == nil else { return }
        guard isWired else { showNotWired(); return }
        let url = store?.mediaURL(item)
        let profile = profile
        preparingItemID = item.id
        Task {
            do {
                let img = try await Self.render(item, mediaURL: url, profile: profile)
                preparingItemID = nil
                send(img, name: item.name, itemID: item.id)
            } catch {
                preparingItemID = nil
                show(error.localizedDescription, error: true)
            }
        }
    }

    nonisolated static func render(_ item: SavedItem, mediaURL: URL?, profile: KeyboardProfile) async throws -> LCDImage {
        switch item.kind {
        case .media:
            guard let url = mediaURL, FileManager.default.fileExists(atPath: url.path) else {
                throw StudioError(message: "The saved file for “\(item.name)” is missing.")
            }
            let media = try await MediaLoader.load(url, videoFPS: item.videoFPS ?? 15, maxFrames: profile.maxFrames)
            return try LCDImage.render(media, mode: ScaleMode(rawValue: item.scaleMode ?? "") ?? .fill,
                                       speed: item.speed ?? 1, profile: profile)
        case .text:
            func tuple(_ c: [UInt8]?, _ d: (UInt8, UInt8, UInt8)) -> (UInt8, UInt8, UInt8) {
                guard let c, c.count == 3 else { return d }
                return (c[0], c[1], c[2])
            }
            let style = Generators.TextStyle(text: item.text ?? "", fontName: item.fontName ?? "Helvetica-Bold",
                                             fontSize: CGFloat(item.fontSize ?? 56),
                                             color: tuple(item.color, (255, 255, 255)),
                                             background: tuple(item.background, (0, 0, 0)),
                                             scrollSpeed: item.scrollSpeed ?? 0)
            return Generators.text(style, profile: profile)
        case .gradient:
            guard let p = Generators.Preset(rawValue: item.preset ?? "") else {
                throw StudioError(message: "Unknown gradient “\(item.preset ?? "")”.")
            }
            return Generators.gradient(p, animated: item.animated ?? true, profile: profile)
        case .solid:
            let c = item.color ?? [0, 0, 0]
            guard c.count == 3 else { throw StudioError(message: "Invalid color for “\(item.name)”.") }
            return LCDImage.solid(red: c[0], green: c[1], blue: c[2], profile: profile)
        }
    }

    // MARK: Presets

    func loadPresetImages() {
        guard presetImages.isEmpty else { return }
        let profile = profile
        Task {
            let images = await Task.detached(priority: .userInitiated) {
                Dictionary(uniqueKeysWithValues: Generators.Preset.allCases.map {
                    ($0.rawValue, Generators.gradient($0, animated: true, profile: profile))
                })
            }.value
            presetImages = images
        }
    }

    func sendPreset(_ preset: Generators.Preset) {
        send(presetImages[preset.rawValue] ?? Generators.gradient(preset, profile: profile), name: preset.name)
    }

    func sendSolid(_ solid: SolidPreset) {
        send(LCDImage.solid(red: solid.rgb[0], green: solid.rgb[1], blue: solid.rgb[2], profile: profile), name: solid.name)
    }

    // MARK: Self test

    /// `-selftest-library YES` saves the `-open` file and a text item once the file has rendered,
    /// so the Library grid has content without any clicking.
    private func runSelfTestIfNeeded() {
        guard pendingSelfTest else { return }
        pendingSelfTest = false
        saveScreenToLibrary()
        let saved = (text, scrolling, textColor)
        text = "Hello from the F108"
        scrolling = true
        textColor = Color(.sRGB, red: 1, green: 0.8, blue: 0.2)
        saveTextToLibrary()
        (text, scrolling, textColor) = saved
        if let i = library.indices.last {
            library[i].lastSent = Date().addingTimeInterval(-2 * 3600)
            saveLibrary()
        }
    }
}
