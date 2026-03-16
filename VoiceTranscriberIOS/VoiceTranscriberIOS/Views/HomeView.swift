import SwiftUI

struct HomeView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Status Card
                    statusCard

                    // Quick Record Button
                    recordButton

                    // Last Transcription
                    if let transcript = appState.lastTranscript {
                        lastTranscriptCard(transcript)
                    }

                    // Today's Stats
                    todayStatsCard

                    // Keyboard Setup Prompt
                    if !appState.config.hasCompletedOnboarding {
                        keyboardSetupCard
                    }
                }
                .padding()
            }
            .navigationTitle("Verbalize")
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(appState.statusMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            if appState.config.translationEnabled {
                Label(
                    SharedConfig.supportedLanguages.first(where: { $0.code == appState.config.targetLanguage })?.name ?? "Translation",
                    systemImage: "globe"
                )
                .font(.caption)
                .foregroundColor(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var statusColor: Color {
        if appState.isRecording { return .red }
        if appState.isProcessing { return .orange }
        if appState.lastError != nil { return .yellow }
        return .green
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button {
            if appState.isRecording {
                appState.stopRecordingAndProcess()
            } else {
                appState.startRecording()
            }
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(appState.isRecording ? Color.red : Color.blue)
                        .frame(width: 80, height: 80)

                    if appState.isRecording {
                        // Waveform animation
                        WaveformView(levels: appState.audioRecorder.audioLevels)
                            .frame(width: 50, height: 30)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                    }
                }

                if appState.isRecording {
                    Text(formatDuration(appState.audioRecorder.recordingDuration))
                        .font(.caption)
                        .foregroundColor(.red)
                        .monospacedDigit()
                } else if appState.isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text("Tap to Record")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .disabled(appState.isProcessing)
        .padding(.vertical, 8)
    }

    // MARK: - Last Transcript Card

    private func lastTranscriptCard(_ transcript: Transcript) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last Transcription")
                    .font(.headline)

                Spacer()

                Button {
                    UIPasteboard.general.string = transcript.cleanedText
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.subheadline)
                }
            }

            Text(transcript.cleanedText)
                .font(.body)
                .lineLimit(5)

            HStack {
                Text(transcript.formattedTimestamp)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(transcript.cleanedText.split(separator: " ").count) words")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Today's Stats

    private var todayStatsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.headline)

            HStack(spacing: 16) {
                StatMiniCard(title: "Words", value: "\(appState.todayWordCount)")
                StatMiniCard(title: "Transcripts", value: "\(appState.todayTranscriptCount)")
                StatMiniCard(title: "Total Words", value: "\(appState.totalWordsTranscribed)")
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Keyboard Setup Card

    private var keyboardSetupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Set Up Keyboard", systemImage: "keyboard")
                .font(.headline)
                .foregroundColor(.blue)

            Text("Install the Verbalize keyboard to use voice-to-text in any app.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Waveform View

struct WaveformView: View {
    let levels: [Float]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(displayLevels.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(width: 2, height: max(2, CGFloat(level) * 30))
            }
        }
    }

    private var displayLevels: [Float] {
        let count = 15
        if levels.count >= count {
            return Array(levels.suffix(count))
        }
        return Array(repeating: Float(0), count: count - levels.count) + levels
    }
}

// MARK: - Stat Mini Card

struct StatMiniCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(8)
    }
}
