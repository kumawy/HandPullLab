import SwiftUI

struct AnimationDebugView: View {
    let controller: HandPullController
    let frames: HandFrameStore
    let replay: () -> Void
    @State private var previewProgress = 0.0

    var body: some View {
        DisclosureGroup("Animation lab") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Эффект включён", isOn: Binding(get: { controller.enabled }, set: {
                    controller.setPreferences(enabled: $0, reduceMotion: controller.reduceMotion)
                }))
                HStack {
                    Button("Replay", action: replay).disabled(controller.reduceMotion || !frames.isReady || !controller.enabled)
                    Spacer()
                    Button("Reset") { controller.reset(); previewProgress = 0 }
                        .accessibilityIdentifier("debug.reset")
                }
                Text("Поза: \(controller.frameIndex) · \(controller.phase.rawValue)")
                    .font(.caption.monospacedDigit())
                Slider(value: $previewProgress, in: 0...1) { Text("Просмотр кадров") }
                    .onChange(of: previewProgress) { _, value in controller.preview(progress: value, framesReady: frames.isReady) }
                    .disabled(controller.reduceMotion || !controller.enabled || !frames.isReady)
                if controller.reduceMotion { Text("Reduce Motion: рука и автоматический возврат отключены.").font(.footnote) }
                Button("Закрыть просмотр кадра") { controller.cancel() }
            }.padding(.top, 12)
        }
        .font(.subheadline)
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("debug.panel")
    }
}
