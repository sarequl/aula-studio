import AppKit
import AulaKit
import SwiftUI

struct LightingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Page {
            WiredNotice(message: "Lighting is set directly on the keyboard. Use the USB cable and set the mode switch to wired.")

            EmbeddedForm {
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                        ForEach(LightingMode.allCases) { mode in
                            ModeChip(mode: mode, selected: model.lighting.mode == mode) {
                                model.lighting.mode = mode
                                model.lightingChanged()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Effect")
                } footer: {
                    Text("Key backlight only. The side light bar is set from the keyboard itself.")
                        .foregroundStyle(.secondary)
                }

                if model.lighting.mode != .off {
                    Section("Settings") {
                        LabeledContent("Color") {
                            HStack(spacing: 12) {
                                Toggle("Rainbow", isOn: bind(\.colorful))
                                ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
                                    .labelsHidden()
                                    .disabled(model.lighting.colorful)
                            }
                        }
                        LabeledContent("Brightness") { stepSlider(\.brightness) }
                        LabeledContent("Speed") { stepSlider(\.speed) }
                        Picker("Direction", selection: bind(\.direction)) {
                            Text("Forward").tag(UInt8(0))
                            Text("Reverse").tag(UInt8(1))
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section {
                    Toggle("Apply changes as you make them", isOn: $model.liveLighting)
                }
            }
            .disabled(!model.isWired)
            .opacity(model.isWired ? 1 : 0.6)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                PrimaryToolbarButton(title: "Apply", symbol: "checkmark.circle.fill", enabled: model.isWired && !model.busy,
                                     help: model.isWired ? "Set this effect on the keyboard (⌘↩)" : "Connect the keyboard over USB in wired mode") {
                    model.applyLighting()
                }
            }
        }
    }

    private func bind<T>(_ kp: WritableKeyPath<LightingConfig, T>) -> Binding<T> {
        Binding(get: { model.lighting[keyPath: kp] },
                set: { model.lighting[keyPath: kp] = $0; model.lightingChanged() })
    }

    private func stepSlider(_ kp: WritableKeyPath<LightingConfig, UInt8>) -> some View {
        HStack(spacing: 8) {
            Slider(value: Binding(get: { Double(model.lighting[keyPath: kp]) },
                                  set: { model.lighting[keyPath: kp] = UInt8($0.rounded()) }),
                   in: 0...5, step: 1) { editing in
                if !editing { model.lightingChanged() }
            }
            Text("\(model.lighting[keyPath: kp])")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                Color(.sRGB, red: Double(model.lighting.red) / 255, green: Double(model.lighting.green) / 255,
                      blue: Double(model.lighting.blue) / 255)
            },
            set: { c in
                let (r, g, b) = AppModel.rgb(c)
                model.lighting.red = r
                model.lighting.green = g
                model.lighting.blue = b
                model.lightingChanged()
            })
    }
}

struct ModeChip: View {
    let mode: LightingMode
    let selected: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected {
                    Image(systemName: "checkmark").font(.caption.weight(.bold))
                }
                Text(mode.name).lineLimit(1).minimumScaleFactor(0.85)
            }
            .font(.callout.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? Color.accentColor : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(selected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
