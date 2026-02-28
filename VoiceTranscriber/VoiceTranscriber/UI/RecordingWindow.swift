import SwiftUI

/// A small floating window that shows a waveform animation during recording.
struct RecordingOverlayView: View {
    @ObservedObject var recorder: AudioRecorder
    @ObservedObject var levelMonitor: AudioLevelMonitor

    @State private var dotCount = 0
    private let dotTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            // Recording indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .opacity(pulseOpacity)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseOpacity)

                Text("Listening" + String(repeating: ".", count: dotCount))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 90, alignment: .leading)
            }

            // Waveform visualization
            WaveformView(levels: levelMonitor.waveformBars)
                .frame(height: 40)

            // Duration
            Text(formattedDuration)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)

            // Cancel hint
            Text("Release to stop • Esc to cancel")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(width: 220)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        )
        .onReceive(dotTimer) { _ in
            dotCount = (dotCount + 1) % 4
        }
    }

    private var pulseOpacity: Double {
        recorder.isRecording ? 1.0 : 0.3
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
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<levels.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(barColor(for: levels[index]))
                        .frame(
                            width: max(2, (geometry.size.width - CGFloat(levels.count - 1) * 2) / CGFloat(levels.count)),
                            height: max(3, CGFloat(levels[index]) * geometry.size.height)
                        )
                        .animation(.easeOut(duration: 0.05), value: levels[index])
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func barColor(for level: Float) -> Color {
        if level > 0.7 { return .red }
        if level > 0.4 { return .orange }
        return .accentColor
    }
}

// MARK: - Floating Window Controller

final class RecordingWindowController: NSObject {
    private var window: NSWindow?
    private var hostingView: NSHostingView<RecordingOverlayView>?

    func show(recorder: AudioRecorder, levelMonitor: AudioLevelMonitor) {
        guard window == nil else { return }

        let contentView = RecordingOverlayView(recorder: recorder, levelMonitor: levelMonitor)
        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = NSRect(x: 0, y: 0, width: 220, height: 140)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 140),
            styleMask: [.nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true

        // Position near top-right of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 240
            let y = screenFrame.maxY - 160
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)
        self.window = panel
        self.hostingView = hosting
    }

    func hide() {
        window?.close()
        window = nil
        hostingView = nil
    }
}
