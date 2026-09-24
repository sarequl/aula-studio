import AppKit
import AulaKit
import SwiftUI

struct LightingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Lighting", subtitle: "Key backlight effect. The side light bar is only adjustable from the keyboard itself.")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8)], spacing: 8) {
                    ForEach(LightingMode.allCases) { mode in
                        ModeChip(mode: mode, selected: model.lighting.mode == mode) {
                            model.lighting.mode = mode
                            model.lightingChanged()
                        }
                    }
                }

                if model.lighting.mode != .off {
                    Form {
                        LabeledContent("Color") {
                            HStack(spacing: 14) {
                                Toggle("Rainbow", isOn: bind(\.colorful))
                                ColorPicker("", selection: colorBinding, supportsOpacity: false)
                                    .labelsHidden()
                                    .disabled(model.lighting.colorful)
                                    .opacity(model.lighting.colorful ? 0.4 : 1)
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
                    .formStyle(.grouped)
                    .scrollDisabled(true)
                    .padding(.horizontal, -20)
                }

                WiredRequiredNote()

                HStack {
                    Toggle("Apply changes instantly", isOn: $model.liveLighting)
                    Spacer()
                    Button("Apply") { model.applyLighting() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!model.isWired || model.busy)
                }
            }
            .padding(28)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    private func bind<T>(_ kp: WritableKeyPath<LightingConfig, T>) -> Binding<T> {
        Binding(get: { model.lighting[keyPath: kp] },
                set: { model.lighting[keyPath: kp] = $0; model.lightingChanged() })
    }

    private func stepSlider(_ kp: WritableKeyPath<LightingConfig, UInt8>) -> some View {
        HStack {
            Slider(value: Binding(get: { Double(model.lighting[keyPath: kp]) },
                                  set: { model.lighting[keyPath: kp] = UInt8($0.rounded()) }),
                   in: 0...5, step: 1) { editing in
                if !editing { model.lightingChanged() }
            }
            Text("\(model.lighting[keyPath: kp])").monospacedDigit().frame(width: 16, alignment: .trailing)
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                Color(.sRGB, red: Double(model.lighting.red) / 255, green: Double(model.lighting.green) / 255,
                      blue: Double(model.lighting.blue) / 255)
            },
            set: { c in
                guard let ns = NSColor(c).usingColorSpace(.sRGB) else { return }
                model.lighting.red = UInt8((ns.redComponent * 255).rounded().clamped(0, 255))
                model.lighting.green = UInt8((ns.greenComponent * 255).rounded().clamped(0, 255))
                model.lighting.blue = UInt8((ns.blueComponent * 255).rounded().clamped(0, 255))
                model.lightingChanged()
            })
    }
}

private extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(Swift.max(self, lo), hi) }
}

struct ModeChip: View {
    let mode: LightingMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(mode.name)
                .font(.callout.weight(selected ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
