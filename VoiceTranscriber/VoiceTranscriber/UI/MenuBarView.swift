import SwiftUI

/// The menu bar extra view that serves as the app's primary interface point.
struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status header
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Divider()

            // Quick actions
            if appState.isRecording {
                Button(action: { appState.cancelRecording() }) {
                    Label("Cancel Recording", systemImage: "xmark.circle")
                }
                .padding(.horizontal, 8)
            } else if appState.isProcessing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Processing...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
            } else {
                Button(action: { appState.showTranscriptHistory() }) {
                    Label("Transcript History", systemImage: "clock.arrow.circlepath")
                }
                .padding(.horizontal, 8)
            }

            // Last transcript preview
            if let last = appState.lastTranscript {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last transcript:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(last.cleanedText)
                        .font(.caption)
                        .lineLimit(3)
                        .frame(maxWidth: 250, alignment: .leading)

                    Button(action: { copyToClipboard(last.cleanedText) }) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
            }

            Divider()

            // Hotkey info
            HStack {
                Text("Hotkey:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(appState.hotkeyDescription)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
            }
            .padding(.horizontal, 12)

            Divider()

            Button(action: { appState.showSettings() }) {
                Label("Settings...", systemImage: "gear")
            }
            .padding(.horizontal, 8)
            .keyboardShortcut(",", modifiers: .command)

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label("Quit VoiceTranscriber", systemImage: "power")
            }
            .padding(.horizontal, 8)
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.vertical, 4)
        .frame(width: 280)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        if appState.isRecording { return .red }
        if appState.isProcessing { return .orange }
        return .green
    }

    private var statusText: String {
        if appState.isRecording { return "Recording..." }
        if appState.isProcessing { return "Processing..." }
        return "Ready"
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
