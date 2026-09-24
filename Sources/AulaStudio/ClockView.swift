import SwiftUI

struct ClockView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("autoSyncClock") private var autoSync = true

    var body: some View {
        Page {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                VStack(spacing: 4) {
                    Text(ctx.date.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 56, weight: .light, design: .rounded).monospacedDigit())
                    Text(ctx.date.formatted(date: .complete, time: .omitted))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityElement(children: .combine)
            }

            WiredNotice(message: "The clock is set over USB. Use the cable and set the mode switch to wired.")

            EmbeddedForm {
                Section {
                    Toggle("Sync when the keyboard is plugged in", isOn: $autoSync)
                    LabeledContent("Last synced") {
                        if let d = model.lastClockSync {
                            Text(d.formatted(date: .omitted, time: .shortened))
                        } else {
                            Text("Not this session")
                        }
                    }
                } footer: {
                    Text("The screen clock drifts and resets when the keyboard loses power. Syncing sets it to this Mac's time.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                PrimaryToolbarButton(title: "Sync Now", symbol: "arrow.triangle.2.circlepath", enabled: model.isWired && !model.busy,
                                     help: model.isWired ? "Set the keyboard clock to this Mac's time (⌘↩)" : "Connect the keyboard over USB in wired mode") {
                    model.syncClock()
                }
            }
        }
    }
}
