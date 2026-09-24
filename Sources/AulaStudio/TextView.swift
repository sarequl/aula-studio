import AulaKit
import SwiftUI

struct TextView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Page {
            KeyboardMockup {
                if let img = model.textRendered {
                    AnimatedLCD(image: img)
                } else {
                    Color.black
                }
            }

            if let img = model.textRendered {
                StatsStrip(items: [
                    ("\(img.frames.count)", img.frames.count == 1 ? "frame" : "frames"),
                    (img.frames.count == 1 ? "Still" : Format.loop(img.totalDuration), "loop"),
                    (Format.duration(img.estimatedUploadSeconds), "to send"),
                ])
            }

            EmbeddedForm {
                Section("Text") {
                    TextField("Text", text: $model.text, prompt: Text("Type something"), axis: .vertical)
                        .lineLimit(1...3)
                    Picker("Font", selection: $model.fontName) {
                        ForEach(TextFonts.all, id: \.name) { Text($0.label).tag($0.name) }
                    }
                    LabeledContent("Size") {
                        HStack(spacing: 8) {
                            Slider(value: $model.fontSize, in: 16...120, step: 1)
                            Text("\(Int(model.fontSize)) pt")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }

                Section("Colors") {
                    ColorPicker("Text", selection: $model.textColor, supportsOpacity: false)
                    ColorPicker("Background", selection: $model.textBackground, supportsOpacity: false)
                }

                Section {
                    Picker("Style", selection: $model.scrolling) {
                        Text("Static").tag(false)
                        Text("Scrolling").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if model.scrolling {
                        LabeledContent("Scroll speed") {
                            HStack(spacing: 8) {
                                Slider(value: $model.scrollSpeed, in: 40...300, step: 10)
                                Text("\(Int(model.scrollSpeed)) px/s")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 64, alignment: .trailing)
                            }
                        }
                    }
                } header: {
                    Text("Motion")
                } footer: {
                    Text(model.scrolling
                         ? "The text crosses the screen once per loop. Long text at low speed is capped at \(model.profile.maxFrames) frames."
                         : "Line breaks become spaces. Text that is too wide shrinks to fit.")
                        .foregroundStyle(.secondary)
                }
            }

            WiredNotice()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.saveTextToLibrary() } label: {
                    Label("Save to Library", systemImage: "square.and.arrow.down.on.square")
                }
                .help("Save this text and its style to the library")
                .disabled(model.flattenedText.isEmpty)

                SendButton(enabled: !model.flattenedText.isEmpty) { model.sendText() }
            }
        }
    }
}
