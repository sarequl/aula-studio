import AppKit
import AulaKit
import SwiftUI

struct SettingsView: View {
    @AppStorage("autoSyncClock") private var autoSync = true
    @AppStorage("defaultScaleMode") private var scaleMode: ScaleMode = .fill
    @AppStorage("defaultVideoFPS") private var videoFPS = 15.0

    var body: some View {
        Form {
            Section {
                Toggle("Sync the clock when the keyboard is plugged in", isOn: $autoSync)
            } header: {
                Text("Clock")
            }

            Section {
                Picker("Scaling", selection: $scaleMode) {
                    ForEach(ScaleMode.allCases) { Text($0.label).tag($0) }
                }
                LabeledContent("Video frame rate") {
                    Stepper(value: $videoFPS, in: 4...30, step: 1) {
                        Text("\(Int(videoFPS)) fps").monospacedDigit()
                    }
                }
            } header: {
                Text("New files")
            } footer: {
                Text("Used when you open a file. Items loaded from the library keep their own settings.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 460, height: 280)
    }
}

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        guard let v = info?["CFBundleShortVersionString"] as? String else { return "Development build" }
        let b = info?["CFBundleVersion"] as? String
        return b.map { "Version \(v) (\($0))" } ?? "Version \(v)"
    }

    /// The bundle icon, or a stand-in when running the bare binary from `swift build`.
    @ViewBuilder private var icon: some View {
        if Bundle.main.bundleURL.pathExtension == "app" {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.28), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
                .frame(width: 84, height: 84)
                .overlay(Image(systemName: "keyboard").font(.system(size: 38, weight: .light)).foregroundStyle(.white))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                .padding(6)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            icon.accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("AULA Studio").font(.title2.weight(.semibold))
                Text(version).font(.callout).foregroundStyle(.secondary)
            }

            Text("Screen, key backlight and clock control for the AULA F108 Pro over USB.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(spacing: 4) {
                Text("Protocol reverse engineering by parsiya").font(.callout)
                Link("github.com/parsiya/f108-pro", destination: Links.protocolNotes).font(.callout)
            }

            Link("Source code on GitHub", destination: Links.repo).font(.callout)

            Text("MIT License. Not affiliated with AULA.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(width: 360)
    }
}
