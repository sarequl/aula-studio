import AulaKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    // Connection
    var connection: ConnectionState = .absent
    var busy = false
    var toast: Toast?

    // Screen
    var sourceURL: URL?
    var source: SourceMedia?
    var rendered: LCDImage?
    var scaleMode: ScaleMode = .fill { didSet { rerender() } }
    var playbackSpeed: Double = 1.0 { didSet { rerender() } }
    var videoFPS: Double = 15
    var loading = false
    var uploadProgress: Double?
    var uploadStarted: Date?

    // Lighting
    var lighting = LightingConfig(mode: .spectrum, red: 0, green: 200, blue: 255, brightness: 4, speed: 3)
    var liveLighting = true

    // Clock
    @ObservationIgnored @AppStorage("autoSyncClock") var autoSyncClock = true

    private let deviceQueue = DispatchQueue(label: "aula.device")
    private var pollTimer: Timer?
    private var renderTask: Task<Void, Never>?
    private var lightingDebounce: Task<Void, Never>?

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    init() {
        refreshConnection()
        // `AulaStudio -open file.gif` loads that file at launch. (A bare path argument would be
        // swallowed by AppKit as an open-file event and suppress the main window.)
        if let path = UserDefaults.standard.string(forKey: "open"), FileManager.default.fileExists(atPath: path) {
            open(URL(fileURLWithPath: path))
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
        connection = currentConnectionState()
        if old != .wired, connection == .wired, autoSyncClock, !busy {
            syncClock(quiet: true)
        }
    }

    func show(_ text: String, error: Bool = false) {
        let t = Toast(text: text, isError: error)
        toast = t
        Task {
            try? await Task.sleep(for: .seconds(error ? 6 : 3))
            if toast == t { toast = nil }
        }
    }

    /// Runs a device operation on the serial device queue.
    private func withDevice(_ label: String, quiet: Bool = false,
                            _ work: @escaping (AulaDevice) throws -> Void) {
        busy = true
        deviceQueue.async {
            let result: Result<Void, Error> = Result { try work(try AulaDevice()) }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success: if !quiet { self.show(label) }
                case .failure(let e): self.show(e.localizedDescription, error: true)
                }
            }
        }
    }

    // MARK: Clock

    func syncClock(quiet: Bool = false) {
        withDevice("Clock synced", quiet: quiet) { try $0.syncClock() }
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

    func open(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        loading = true
        sourceURL = url
        let fps = videoFPS
        Task {
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let media = try await MediaLoader.load(url, videoFPS: fps)
                source = media
                rerender()
            } catch {
                loading = false
                show(error.localizedDescription, error: true)
            }
        }
    }

    func reloadVideo() {
        if let url = sourceURL, isVideo { open(url) }
    }

    func rerender() {
        guard let media = source else { return }
        let mode = scaleMode, speed = playbackSpeed
        renderTask?.cancel()
        loading = true
        renderTask = Task.detached(priority: .userInitiated) {
            let result = Result { try LCDImage.render(media, mode: mode, speed: speed) }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.loading = false
                switch result {
                case .success(let img): self.rendered = img
                case .failure(let e): self.show(e.localizedDescription, error: true)
                }
            }
        }
    }

    func upload() {
        guard let img = rendered, !busy else { return }
        let data: Data
        do { data = try img.encode() } catch {
            show(error.localizedDescription, error: true)
            return
        }
        uploadProgress = 0
        uploadStarted = Date()
        withDevice("Uploaded. The keyboard is saving it now.") { dev in
            defer { DispatchQueue.main.async { self.uploadProgress = nil; self.uploadStarted = nil } }
            try dev.uploadScreen(data) { sent, total in
                DispatchQueue.main.async { self.uploadProgress = Double(sent) / Double(total) }
            }
        }
    }
}
