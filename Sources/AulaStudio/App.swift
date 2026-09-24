import AppKit
import AulaKit
import SwiftUI

@main
struct AulaStudioApp: App {
    @State private var model = AppModel()

    init() {
        // Launched as a bare executable (swift run) there is no bundle to make us a regular app.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("AULA Studio") {
            ContentView()
                .environment(model)
                .frame(minWidth: 760, idealWidth: 860, minHeight: 640, idealHeight: 820)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 860, height: 820)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

enum Section: String, CaseIterable, Identifiable {
    case screen = "Screen", lighting = "Lighting", clock = "Clock"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .screen: "photo.on.rectangle.angled"
        case .lighting: "light.max"
        case .clock: "clock"
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var section: Section? =
        Section(rawValue: (UserDefaults.standard.string(forKey: "tab") ?? "").capitalized) ?? .screen

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $section) {
                    ForEach(Section.allCases) { s in
                        Label(s.rawValue, systemImage: s.icon).tag(s)
                    }
                }
                .listStyle(.sidebar)
                .padding(.top, 30)
                ConnectionBadge().padding(12)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 220)
        } detail: {
            Group {
                switch section ?? .screen {
                case .screen: ScreenView()
                case .lighting: LightingView()
                case .clock: ClockView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) { ToastView() }
        }
    }
}

struct ConnectionBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var color: Color {
        switch model.connection {
        case .wired: .green
        case .wireless: .orange
        case .absent: .secondary
        }
    }
    private var title: String {
        switch model.connection {
        case .wired: "F108 Pro · USB"
        case .wireless: "F108 Pro · Wireless"
        case .absent: "Not connected"
        }
    }
    private var detail: String {
        switch model.connection {
        case .wired: model.busy ? "Talking to keyboard…" : "Ready"
        case .wireless: "Plug in the USB cable and set the mode switch to wired to make changes."
        case .absent: "Connect the keyboard with its USB cable."
        }
    }
}

struct WiredRequiredNote: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if !model.isWired {
            Label(model.connection == .wireless
                  ? "Your keyboard is on Bluetooth/2.4G. The screen and lighting can only be changed over the USB cable with the switch set to wired."
                  : "Connect the keyboard with its USB cable (mode switch on wired).",
                  systemImage: "cable.connector")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let t = model.toast {
            Label(t.text, systemImage: t.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(t.isError ? .red : .primary)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 8, y: 2)
                .padding(.bottom, 18)
                .padding(.horizontal, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(t.id)
        }
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.largeTitle.weight(.semibold))
            Text(subtitle).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
