import AppKit
import AulaKit
import SwiftUI

@main
struct AulaStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    init() {
        // Launched as a bare executable (swift run) there is no bundle to make us a regular app.
        NSApplication.shared.setActivationPolicy(.regular)
        // `-appearance light|dark` forces an appearance (used for screenshots).
        switch UserDefaults.standard.string(forKey: "appearance")?.lowercased() {
        case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case "dark": NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    var body: some Scene {
        WindowGroup("AULA Studio", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 860, minHeight: 640)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 780)
        .commands {
            CommandGroup(replacing: .appInfo) { AboutCommand() }
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    model.pane = .screen
                    model.importing = true
                }
                .keyboardShortcut("o")
            }
            CommandGroup(before: .sidebar) {
                ForEach(Pane.allCases) { pane in
                    Button(pane.title) { model.pane = pane }
                        .keyboardShortcut(pane.shortcut, modifiers: .command)
                }
                Divider()
            }
            CommandGroup(replacing: .help) {
                Button("AULA Studio on GitHub") { NSWorkspace.shared.open(Links.repo) }
                Button("F108 Pro Protocol Notes") { NSWorkspace.shared.open(Links.protocolNotes) }
            }
        }

        Window("About AULA Studio", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)

        Settings {
            SettingsView()
        }
    }
}

private struct AboutCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("About AULA Studio") { openWindow(id: "about") }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard AppModel.shared.uploading else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "A screen upload is in progress"
        alert.informativeText = "Quitting now stops the transfer and leaves the keyboard's screen partly written. You can send it again afterwards."
        alert.addButton(withTitle: "Keep Sending")
        alert.addButton(withTitle: "Quit Anyway")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: Binding<Pane?>(get: { model.pane }, set: { if let p = $0 { model.pane = p } })) {
                Section("Display") {
                    row(.screen)
                    row(.library)
                    row(.text)
                }
                Section("Keyboard") {
                    row(.lighting)
                    row(.keys)
                    row(.remap)
                    row(.clock)
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ConnectionBadge().padding(12)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 260)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(model.pane.title)
                .overlay(alignment: .bottom) {
                    VStack(spacing: 0) {
                        ToastView()
                        UploadBanner()
                    }
                }
                .animation(.snappy, value: model.uploading)
        }
        .fileImporter(isPresented: $model.importing,
                      allowedContentTypes: [.gif, .image, .movie, .mpeg4Movie, .quickTimeMovie]) { result in
            switch result {
            case .success(let url): model.open(url)
            case .failure(let e): model.show(e.localizedDescription, error: true)
            }
        }
        .onAppear {
            // `-open-window about|settings` opens that window at launch (used for screenshots).
            switch UserDefaults.standard.string(forKey: "open-window") {
            case "about": openWindow(id: "about")
            case "settings": openSettings()
            default: break
            }
            // `-window-size 860x640` resizes the main window at launch (used to check the minimum size).
            if let spec = UserDefaults.standard.string(forKey: "window-size") {
                let parts = spec.split(separator: "x").compactMap { Double($0) }
                if parts.count == 2 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        guard let win = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") ?? false }) ?? NSApp.mainWindow else { return }
                        win.setContentSize(NSSize(width: parts[0], height: parts[1]))
                    }
                }
            }
        }
    }

    private func row(_ pane: Pane) -> some View {
        Label(pane.title, systemImage: pane.icon).tag(pane)
    }

    @ViewBuilder private var detail: some View {
        switch model.pane {
        case .screen: ScreenView()
        case .library: LibraryView()
        case .text: TextView()
        case .lighting: LightingView()
        case .keys: KeysView()
        case .remap: RemapView()
        case .clock: ClockView()
        }
    }
}
