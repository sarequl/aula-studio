import AulaKit
import SwiftUI
import UniformTypeIdentifiers

struct ScreenView: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Screen", subtitle: "Put a GIF, picture or video clip on the keyboard's display.")

                preview
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let u = urls.first else { return false }
                        model.open(u)
                        return true
                    } isTargeted: { dropTargeted = $0 }

                if let img = model.rendered {
                    stats(img)
                }

                if model.source != nil {
                    controls
                }

                WiredRequiredNote()
                uploadBar
            }
            .padding(28)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.gif, .image, .movie, .mpeg4Movie, .quickTimeMovie]) { result in
            if case .success(let url) = result { model.open(url) }
        }
    }

    // MARK: Preview

    private var preview: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.25), radius: 14, y: 6)

                Group {
                    if let img = model.rendered {
                        AnimatedLCD(image: img)
                    } else {
                        emptyScreen
                    }
                }
                .frame(width: 480, height: 270)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.08)))
                .overlay {
                    if model.loading { ProgressView().controlSize(.large).tint(.white) }
                }
            }
            .frame(width: 528, height: 318)
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Color.accentColor, lineWidth: dropTargeted ? 3 : 0)
            )

            HStack {
                Button { importing = true } label: {
                    Label(model.source == nil ? "Choose File…" : "Replace…", systemImage: "folder")
                }
                if let url = model.sourceURL {
                    Text(url.lastPathComponent).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyScreen: some View {
        ZStack {
            Color.black
            VStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down").font(.system(size: 30, weight: .light))
                Text("Drop a GIF, image or video").font(.headline)
                Text("240 × 135 screen").font(.caption).opacity(0.6)
            }
            .foregroundStyle(.white.opacity(0.75))
        }
    }

    // MARK: Info + controls

    private func stats(_ img: LCDImage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 18) {
                stat("\(img.frames.count)", img.frames.count == 1 ? "frame" : "frames")
                stat(String(format: "%.1f s", img.totalDuration), "loop")
                stat(ByteCountFormatter.string(fromByteCount: Int64(img.pageCount * 4096), countStyle: .file), "on keyboard")
                stat(duration(img.estimatedUploadSeconds), "upload time")
            }
            if img.sourceFrameCount > img.frames.count {
                Label("The keyboard stores at most \(img.profile.maxFrames) frames, so \(img.sourceFrameCount) frames were thinned to \(img.frames.count). Playback speed is kept.",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title3.monospacedDigit().weight(.medium))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        @Bindable var model = model
        return Form {
            Picker("Scaling", selection: $model.scaleMode) {
                ForEach(ScaleMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            LabeledContent("Speed") {
                HStack {
                    Slider(value: $model.playbackSpeed, in: 0.25...4, step: 0.25)
                    Text(String(format: "%.2g×", model.playbackSpeed)).monospacedDigit().frame(width: 40, alignment: .trailing)
                }
            }
            .disabled((model.rendered?.frames.count ?? 0) < 2)

            if model.isVideo {
                LabeledContent("Video frame rate") {
                    HStack {
                        Slider(value: $model.videoFPS, in: 4...30, step: 1) { editing in
                            if !editing { model.reloadVideo() }
                        }
                        Text("\(Int(model.videoFPS)) fps").monospacedDigit().frame(width: 50, alignment: .trailing)
                    }
                }
                Text("Clips are capped at \(model.profile.maxFrames) frames. Higher frame rates mean a shorter loop.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .padding(.horizontal, -20)
    }

    // MARK: Upload

    private var uploadBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let p = model.uploadProgress {
                ProgressView(value: p) {
                    HStack {
                        Text("Uploading… keep the cable plugged in")
                        Spacer()
                        Text(eta(p)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
            HStack {
                Spacer()
                Button {
                    model.upload()
                } label: {
                    Label("Send to Keyboard", systemImage: "arrow.up.circle.fill")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.rendered == nil || !model.isWired || model.busy || model.loading)
            }
        }
    }

    private func eta(_ p: Double) -> String {
        guard let start = model.uploadStarted, p > 0.01 else { return "" }
        let elapsed = Date().timeIntervalSince(start)
        return duration(elapsed / p - elapsed) + " left"
    }

    private func duration(_ s: Double) -> String {
        let s = Int(s.rounded())
        return s < 60 ? "\(s) s" : "\(s / 60) min \(s % 60) s"
    }
}

/// Plays the rendered frames with their real per-frame delays.
struct AnimatedLCD: View {
    let image: LCDImage
    private let ends: [Double]
    private let frames: [Image]

    init(image: LCDImage) {
        self.image = image
        var t = 0.0
        ends = image.delays.map { t += $0; return t }
        frames = image.frames.map { Image(decorative: $0, scale: 1).interpolation(.none) }
    }

    var body: some View {
        TimelineView(.animation(paused: frames.count < 2)) { ctx in
            frames[index(at: ctx.date)]
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }

    private func index(at date: Date) -> Int {
        guard frames.count > 1, let total = ends.last, total > 0 else { return 0 }
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: total)
        return ends.firstIndex { t < $0 } ?? frames.count - 1
    }
}
