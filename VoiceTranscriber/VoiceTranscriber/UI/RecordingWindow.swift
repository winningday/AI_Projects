import SwiftUI

/// A small floating window that shows a waveform animation during recording.
struct RecordingOverlayView: View {
    @ObservedObject var recorder: AudioRecorder
    @ObservedObject var levelMonitor: AudioLevelMonitor

    @State private var dotCount = 0
    @State private var pulse = false
    private let dotTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 14) {
            // Recording indicator with pulsing dot
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 18, height: 18)
                        .scaleEffect(pulse ? 1.3 : 1.0)
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }

                Text("Listening" + String(repeating: ".", count: dotCount))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .frame(width: 100, alignment: .leading)

                Spacer()

                // Duration badge
                Text(formattedDuration)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }

            // Waveform visualization
            WaveformView(levels: levelMonitor.waveformBars)
                .frame(height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Level meter
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(nsColor: .separatorColor).opacity(0.3))

                    Capsule()
                        .fill(levelColor)
                        .frame(width: max(4, geo.size.width * CGFloat(levelMonitor.smoothedLevel)))
                        .animation(.easeOut(duration: 0.08), value: levelMonitor.smoothedLevel)
                }
            }
            .frame(height: 4)

            // Cancel hint
            Text("Release to stop  \u{2022}  Esc to cancel")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        }
        .padding(20)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
        .onReceive(dotTimer) { _ in
            dotCount = (dotCount + 1) % 4
        }
    }

    private var levelColor: LinearGradient {
        LinearGradient(
            colors: [.green, .yellow, .orange, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var formattedDuration: String {
        let seconds = Int(recorder.recordingDuration)
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Waveform View

struct WaveformView: View {
    let levels: [Float]

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 1.5) {
                ForEach(0..<levels.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barGradient(for: levels[index]))
                        .frame(
                            width: max(2, (geometry.size.width - CGFloat(levels.count - 1) * 1.5) / CGFloat(levels.count)),
                            height: max(3, CGFloat(levels[index]) * geometry.size.height)
                        )
                        .animation(.easeOut(duration: 0.06), value: levels[index])
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func barGradient(for level: Float) -> LinearGradient {
        let color: Color = level > 0.7 ? .red : (level > 0.4 ? .orange : .accentColor)
        return LinearGradient(
            colors: [color.opacity(0.6), color],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}

// MARK: - Floating Window Controller

final class RecordingWindowController: NSObject {
    private var window: NSPanel?

    func show(recorder: AudioRecorder, levelMonitor: AudioLevelMonitor) {
        guard window == nil else { return }

        let contentView = RecordingOverlayView(recorder: recorder, levelMonitor: levelMonitor)
        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = NSRect(x: 0, y: 0, width: 260, height: 170)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 170),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true

        // Position near top-right of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 280
            let y = screenFrame.maxY - 190
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)
        self.window = panel
    }

    func hide() {
        window?.close()
        window = nil
    }
}
