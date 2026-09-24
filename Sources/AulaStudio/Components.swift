import AppKit
import AulaKit
import SwiftUI

enum Links {
    static let protocolNotes = URL(string: "https://github.com/parsiya/f108-pro")!
    static let repo = URL(string: "https://github.com/sarequl/aula-keyboard")!
}

enum Format {
    static func duration(_ s: Double) -> String {
        let s = max(0, Int(s.rounded()))
        if s < 60 { return "\(s) s" }
        return s % 60 == 0 ? "\(s / 60) min" : "\(s / 60) min \(s % 60) s"
    }
    static func loop(_ s: Double) -> String { String(format: "%.1f s", s) }
    static func frames(_ n: Int) -> String { n == 1 ? "1 frame" : "\(n) frames" }
    static func size(pages: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(pages * 4096), countStyle: .file)
    }
}

// MARK: Keyboard mockup

/// A dark keyboard body around the LCD, drawn at 2x (480x270 screen) and scaled down
/// only when the column is narrower than the design.
struct KeyboardMockup<Screen: View>: View {
    var highlighted = false
    var loading = false
    @ViewBuilder var screen: () -> Screen

    private static var design: CGSize { CGSize(width: 600, height: 372) }

    var body: some View {
        let d = Self.design
        GeometryReader { geo in
            let s = min(1, geo.size.width / d.width)
            keyboard
                .frame(width: d.width, height: d.height)
                .scaleEffect(s, anchor: .topLeading)
        }
        .aspectRatio(d.width / d.height, contentMode: .fit)
        .frame(maxWidth: d.width)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keyboard screen preview")
    }

    private var keyboard: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.21), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.02)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1)
                )

            VStack(spacing: 18) {
                HStack(alignment: .top, spacing: 20) {
                    screenWell
                    VStack(spacing: 16) {
                        Knob()
                        VStack(spacing: 7) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle().fill(i == 0 ? Color.green.opacity(0.8) : Color.white.opacity(0.12))
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }
                    .frame(width: 44)
                    .padding(.top, 6)
                }
                KeyRow()
            }
            .padding(20)
        }
        .mask(
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.84),
                                   .init(color: .black.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        )
        .environment(\.colorScheme, .dark)
    }

    private var screenWell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black)
            screen()
                .frame(width: 480, height: 270)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .overlay {
                    LinearGradient(colors: [.white.opacity(0.07), .clear], startPoint: .topLeading, endPoint: .center)
                        .allowsHitTesting(false)
                }
                .overlay {
                    if loading {
                        ZStack {
                            Color.black.opacity(0.35)
                            ProgressView().controlSize(.large)
                        }
                    }
                }
        }
        .frame(width: 496, height: 286)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(highlighted ? Color.accentColor : .white.opacity(0.07), lineWidth: highlighted ? 3 : 1)
        )
    }
}

private struct Knob: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: [Color(white: 0.42), Color(white: 0.2), Color(white: 0.38), Color(white: 0.18), Color(white: 0.42)],
                                      center: .center))
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.3), Color(white: 0.2)], center: .topLeading, startRadius: 2, endRadius: 40))
                .padding(5)
            Capsule().fill(.white.opacity(0.5)).frame(width: 2, height: 8).offset(y: -12)
        }
        .frame(width: 44, height: 44)
        .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
    }
}

private struct KeyRow: View {
    private let groups = [["esc"], ["F1", "F2", "F3", "F4"], ["F5", "F6", "F7", "F8"], ["F9", "F10", "F11", "F12"]]
    var body: some View {
        HStack(spacing: 14) {
            ForEach(groups, id: \.self) { g in
                HStack(spacing: 5) {
                    ForEach(g, id: \.self) { Keycap(label: $0) }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct Keycap: View {
    let label: String
    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.11)], startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.26), Color(white: 0.19)], startPoint: .top, endPoint: .bottom))
                    .padding(EdgeInsets(top: 2, leading: 3, bottom: 6, trailing: 3))
            )
            .overlay(alignment: .topLeading) {
                Text(label).font(.system(size: 8.5, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 6).padding(.leading, 7)
            }
            .frame(width: 36, height: 40)
    }
}

/// What the screen shows before anything is loaded.
struct EmptyLCD: View {
    let symbol: String
    let title: String
    let subtitle: String
    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 30, weight: .light))
                Text(title).font(.headline)
                Text(subtitle).font(.caption).opacity(0.6)
            }
            .foregroundStyle(.white.opacity(0.75))
        }
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

// MARK: Stats

struct StatsStrip: View {
    let items: [(value: String, label: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                if i > 0 { Divider().frame(height: 30) }
                VStack(spacing: 2) {
                    Text(item.value).font(.title3.weight(.semibold).monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(item.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    static func upload(_ img: LCDImage) -> StatsStrip {
        StatsStrip(items: [
            ("\(img.frames.count)", img.frames.count == 1 ? "frame" : "frames"),
            (img.frames.count == 1 ? "Still" : Format.loop(img.totalDuration), "loop"),
            (Format.size(pages: img.pageCount), "on keyboard"),
            (Format.duration(img.estimatedUploadSeconds), "to send"),
        ])
    }
}

/// Embeds a grouped form in a scrolling page without its own scrolling or side inset.
struct EmbeddedForm<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        Form { content() }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, -20)
            .padding(.vertical, -12)
    }
}

// MARK: Connection

struct ConnectionBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(color.opacity(0.22)).frame(width: 16, height: 16)
                Circle().fill(color).frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium)).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if model.busy { ProgressView().controlSize(.small) }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .help(help)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch model.connection {
        case .wired: .green
        case .wireless: .orange
        case .absent: .gray
        }
    }
    private var title: String {
        model.connection == .absent ? "No keyboard" : model.profile.name
    }
    private var detail: String {
        switch model.connection {
        case .wired: model.uploading ? "USB · Sending" : "USB"
        case .wireless: "Wireless · input only"
        case .absent: "Not connected"
        }
    }
    private var help: String {
        switch model.connection {
        case .wired: "Connected over USB. Screen, lighting and clock are available."
        case .wireless: "Bluetooth and 2.4G only carry key presses. Use the USB cable with the mode switch on wired."
        case .absent: "Connect the keyboard with its USB cable and set the mode switch to wired."
        }
    }
}

/// Explains why sending is unavailable. Shown only when the keyboard isn't on USB.
struct WiredNotice: View {
    @Environment(AppModel.self) private var model
    var message: String?

    var body: some View {
        if !model.isWired {
            let wireless = model.connection == .wireless
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: wireless ? "antenna.radiowaves.left.and.right.slash" : "cable.connector")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(wireless ? "Switch the keyboard to wired mode" : "Connect the keyboard over USB").font(.headline)
                    Text(wireless
                         ? "Bluetooth and 2.4G only carry key presses. Plug in the USB cable and set the mode switch to wired."
                         : (message ?? "Use the USB cable and set the mode switch to wired. You can still prepare and save screens without it."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.orange.opacity(0.25)))
        }
    }
}

// MARK: Sending

struct SendButton: View {
    @Environment(AppModel.self) private var model
    var title = "Send to Keyboard"
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        PrimaryToolbarButton(title: title, symbol: "arrow.up.circle.fill",
                             enabled: enabled && model.isWired && !model.busy,
                             help: model.isWired ? "Upload to the keyboard's screen (⌘↩)" : "Connect the keyboard over USB in wired mode to send",
                             action: action)
    }
}

/// Prominent when it can be used; a plain bordered button otherwise, since a disabled
/// prominent button reads as active in the toolbar.
struct PrimaryToolbarButton: View {
    let title: String
    let symbol: String
    let enabled: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            Label(title, systemImage: symbol).labelStyle(.titleAndIcon)
        }
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!enabled)
        .help(help)
        if enabled { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
    }
}

struct UploadBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let p = model.uploadProgress {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill").foregroundStyle(.tint)
                    Text("Sending “\(model.uploadName)”").font(.headline).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(eta(p, now: ctx.date)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: p)
                Label("Keep the USB cable plugged in. When the transfer ends, the keyboard shows its own progress bar while it saves.",
                      systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: 720)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func eta(_ p: Double, now: Date) -> String {
        guard let start = model.uploadStarted, p > 0.02 else { return "Starting…" }
        let elapsed = now.timeIntervalSince(start)
        return Format.duration(elapsed / p - elapsed) + " left"
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let t = model.toast {
            Label(t.text, systemImage: t.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .symbolRenderingMode(.multicolor)
                .font(.callout)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
                .frame(maxWidth: 520)
                .padding(.bottom, 20)
                .padding(.horizontal, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(t.id)
        }
    }
}

/// Page scaffold: centered column, 24 pt margins, 20 pt between blocks.
struct Page<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content() }
                .padding(24)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
        }
        // Room to scroll past the upload banner, which floats over the bottom edge.
        .contentMargins(.bottom, model.uploading ? 120 : 0, for: .scrollContent)
    }
}
