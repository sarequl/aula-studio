import AppKit
import AulaKit
import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("librarySort") private var sort: LibrarySort = .lastSent
    @State private var renaming: UUID?
    @State private var deleting: SavedItem?

    var body: some View {
        Page {
            header("Presets", "Built-in screens you can send as they are.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 150), spacing: 12)], spacing: 12) {
                ForEach(Generators.Preset.allCases) { preset in
                    PresetCard(name: preset.name, detail: "Gradient") {
                        if let img = model.presetImages[preset.rawValue] { AnimatedLCD(image: img) } else { Color.black }
                    } send: { model.sendPreset(preset) }
                }
                ForEach(SolidPreset.all) { solid in
                    PresetCard(name: solid.name, detail: "Solid color") {
                        solid.color
                    } send: { model.sendSolid(solid) }
                }
            }

            header("Saved", "GIFs, videos and text you saved, with their settings.")
                .padding(.top, 8)

            if model.library.isEmpty {
                empty
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)], spacing: 20) {
                    ForEach(model.sortedLibrary(sort)) { item in
                        LibraryCard(item: item, renaming: $renaming) { deleting = item }
                    }
                }
            }

            WiredNotice(message: "Use the USB cable and set the mode switch to wired to send items to the screen.")
        }
        .onAppear { model.loadPresetImages() }
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { item in
            Button("Delete", role: .destructive) { model.delete(item) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It is removed from the library. The keyboard keeps showing whatever it has now.")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort By", selection: $sort) {
                        ForEach(LibrarySort.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort By", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort saved items")
                .disabled(model.library.count < 2)
            }
        }
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("Nothing saved yet", systemImage: "square.stack")
        } description: {
            Text("Use Save to Library in Screen or Text to keep a GIF, video or text here with its scaling and speed. Anything saved can be sent again in one click.")
        } actions: {
            HStack {
                Button("Open Screen") { model.pane = .screen }
                Button("Open Text") { model.pane = .text }
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: Cards

/// Thumbnail frame at the screen's 16:9 aspect ratio.
private struct Thumb<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        Color.black
            .aspectRatio(240.0 / 135.0, contentMode: .fit)
            .overlay { content() }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator))
    }
}

private struct PresetCard<Preview: View>: View {
    @Environment(AppModel.self) private var model
    let name: String
    let detail: String
    @ViewBuilder var preview: () -> Preview
    let send: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Thumb(content: preview)
                .overlay {
                    if hovering {
                        ZStack {
                            Color.black.opacity(0.35)
                            Button("Send", systemImage: "arrow.up.circle.fill", action: send)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(!model.isWired || model.busy)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.callout.weight(.medium)).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .contextMenu {
            Button("Send to Keyboard", action: send).disabled(!model.isWired || model.busy)
        }
    }
}

private struct LibraryCard: View {
    @Environment(AppModel.self) private var model
    let item: SavedItem
    @Binding var renaming: UUID?
    let delete: () -> Void
    @State private var hovering = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    private var canSend: Bool { model.isWired && !model.busy && model.preparingItemID == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Thumb {
                if let img = model.thumbnails[item.id] {
                    Image(nsImage: img).resizable().interpolation(.none).aspectRatio(contentMode: .fill)
                }
            }
            .overlay(alignment: .topLeading) { kindBadge.padding(6) }
            .overlay { hoverActions }

            VStack(alignment: .leading, spacing: 2) {
                if renaming == item.id {
                    TextField("Name", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                        .onSubmit(commitRename)
                        .onExitCommand { renaming = nil }
                        .onChange(of: nameFocused) { _, focused in if !focused { commitRename() } }
                } else {
                    Text(item.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(item.name)
                        .onTapGesture(count: 2) { startRename() }
                }
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(sentText).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .contextMenu { menuItems }
    }

    private var kindBadge: some View {
        Image(systemName: item.kind == .text ? "textformat" : (item.frameCount > 1 ? "film" : "photo"))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(5)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    @ViewBuilder private var hoverActions: some View {
        if model.preparingItemID == item.id {
            ZStack {
                Color.black.opacity(0.45)
                ProgressView().controlSize(.small)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .environment(\.colorScheme, .dark)
        } else if hovering && renaming != item.id {
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                HStack(spacing: 6) {
                    Button("Send", systemImage: "arrow.up.circle.fill") { model.sendItem(item) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSend)
                        .help(model.isWired ? "Send to the keyboard" : "Connect the keyboard over USB in wired mode to send")
                    if let load = loadLabel {
                        Button(load) { load == "Edit" ? model.loadIntoText(item) : model.loadIntoScreen(item) }
                            .buttonStyle(.bordered)
                            .help(item.kind == .text ? "Load into Text" : "Load into Screen")
                    }
                    Spacer(minLength: 0)
                    Menu {
                        menuItems
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .controlSize(.small)
                .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .environment(\.colorScheme, .dark)
        }
    }

    private var loadLabel: String? {
        switch item.kind {
        case .media: "Open"
        case .text: "Edit"
        case .gradient, .solid: nil
        }
    }

    @ViewBuilder private var menuItems: some View {
        Button("Send to Keyboard") { model.sendItem(item) }.disabled(!canSend)
        if item.kind == .media { Button("Load into Screen") { model.loadIntoScreen(item) } }
        if item.kind == .text { Button("Load into Text") { model.loadIntoText(item) } }
        Divider()
        Button("Rename") { startRename() }
        Button("Delete…", role: .destructive, action: delete)
    }

    private var summary: String {
        if item.frameCount <= 1 { return item.kind == .text ? "Static text" : "Still image" }
        return "\(Format.frames(item.frameCount)) · \(Format.loop(item.duration))"
    }

    private var sentText: String {
        guard let d = item.lastSent else { return "Not sent yet" }
        return "Sent " + d.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }

    private func startRename() {
        draft = item.name
        renaming = item.id
        DispatchQueue.main.async { nameFocused = true }
    }

    private func commitRename() {
        guard renaming == item.id else { return }
        model.rename(item, to: draft)
        renaming = nil
    }
}
