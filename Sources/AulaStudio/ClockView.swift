import SwiftUI

struct ClockView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Clock", subtitle: "The keyboard's screen clock drifts and resets when it loses power. Sync it to this Mac.")

                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    VStack(spacing: 4) {
                        Text(ctx.date.formatted(date: .omitted, time: .standard))
                            .font(.system(size: 54, weight: .light, design: .rounded).monospacedDigit())
                        Text(ctx.date.formatted(date: .complete, time: .omitted))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
                }

                WiredRequiredNote()

                HStack {
                    Toggle("Sync automatically when the keyboard is plugged in", isOn: $model.autoSyncClock)
                    Spacer()
                    Button("Sync Now") { model.syncClock() }
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
}
