import AulaKit
import SwiftUI
import UniformTypeIdentifiers

struct ScreenView: View {
    @Environment(AppModel.self) private var model
    @State private var dropTargeted = false

    var body: some View {
        Page {
            KeyboardMockup(highlighted: dropTargeted, loading: model.loading) {
                if let img = model.rendered {
                    AnimatedLCD(image: img)
                } else {
                    EmptyLCD(symbol: "square.and.arrow.down", title: "Drop a GIF, image or video", subtitle: "240 × 135 screen")
                }
            }

            fileRow

            if let img = model.rendered {
                VStack(alignment: .leading, spacing: 8) {
                    StatsStrip.upload(img)
                    if img.sourceFrameCount > img.frames.count {
                        Label("Reduced from \(img.sourceFrameCount) to \(img.frames.count) frames to fit the keyboard. The loop keeps its length.",
                              systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if model.source != nil { controls } else { facts }

            WiredNotice()
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let u = urls.first else { return false }
            model.open(u)
            return true
        } isTargeted: { dropTargeted = $0 }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.importing = true } label: {
                    Label("Choose File", systemImage: "folder")
                }
                .help("Choose a GIF, image or video (⌘O)")

                Button { model.saveScreenToLibrary() } label: {
                    Label("Save to Library", systemImage: "square.and.arrow.down.on.square")
                }
                .help(model.screenItemID == nil ? "Save this file and its settings to the library" : "Update the library item with these settings")
                .disabled(model.rendered == nil || model.loading)

                SendButton(enabled: model.rendered != nil && !model.loading) { model.sendScreen() }
            }
        }
    }

    private var fileRow: some View {
        HStack(spacing: 8) {
            if let url = model.sourceURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(model.sourceName ?? url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if model.screenItemID != nil {
                    Text("Library")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Replace…") { model.importing = true }
            } else {
                Text("Drop a file on the screen above, or")
                    .foregroundStyle(.secondary)
                Button("Choose File…") { model.importing = true }
            }
        }
        .frame(maxWidth: .infinity, alignment: model.sourceURL == nil ? .center : .leading)
    }

    private var controls: some View {
        @Bindable var model = model
        return EmbeddedForm {
            Section {
                Picker("Scaling", selection: $model.scaleMode) {
                    ForEach(ScaleMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                LabeledContent("Speed") {
                    HStack(spacing: 8) {
                        Slider(value: $model.playbackSpeed, in: 0.25...4, step: 0.25)
                        Text(String(format: "%.2g×", model.playbackSpeed))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                .disabled((model.rendered?.frames.count ?? 0) < 2)

                if model.isVideo {
                    LabeledContent("Video frame rate") {
                        HStack(spacing: 8) {
                            Slider(value: $model.videoFPS, in: 4...30, step: 1) { editing in
                                if !editing { model.reloadVideo() }
                            }
                            Text("\(Int(model.videoFPS)) fps")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }
            } header: {
                Text("Playback")
            } footer: {
                if model.isVideo {
                    Text("Clips are sampled at this rate, up to \(model.profile.maxFrames) frames. A higher rate means a shorter loop.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var facts: some View {
        EmbeddedForm {
            Section("What the screen takes") {
                Label("GIF, PNG, JPEG, HEIC, WebP, MP4 or MOV", systemImage: "photo.stack")
                Label("Up to \(model.profile.maxFrames) frames. Longer media is thinned evenly and keeps its length.", systemImage: "film.stack")
                Label("A full upload takes about 2.5 minutes over USB. Leave the cable plugged in until the keyboard finishes saving.", systemImage: "clock.arrow.circlepath")
            }
        }
    }
}
