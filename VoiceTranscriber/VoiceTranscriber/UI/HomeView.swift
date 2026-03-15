import SwiftUI

/// Home tab showing stats dashboard and recent transcript history.
struct HomeView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Stats row
                HStack(spacing: 12) {
                    StatCard(
                        title: "Words",
                        value: formatNumber(appState.totalWordsTranscribed),
                        icon: "character.cursor.ibeam",
                        color: .blue
                    )
                    StatCard(
                        title: "WPM",
                        value: "\(appState.wordsPerMinute)",
                        icon: "gauge.with.dots.needle.33percent",
                        color: .green
                    )
                    StatCard(
                        title: "Transcripts",
                        value: "\(appState.database.transcripts.count)",
                        icon: "doc.text",
                        color: .purple
                    )
                    StatCard(
                        title: "Time Saved",
                        value: formatTimeSaved(appState.totalRecordingSeconds),
                        icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        color: .orange
                    )
                }

                // Quick action banner
                QuickActionBanner(appState: appState)

                // Error banner
                if let error = appState.lastError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 12))
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Spacer()
                        Button(action: { appState.lastError = nil }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.orange.opacity(0.15), lineWidth: 0.5)
                            )
                    )
                }

                // Translation indicator
                if appState.config.translationEnabled {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                            .foregroundColor(.blue)
                            .font(.system(size: 12))
                        let langName = ConfigManager.supportedLanguages.first(where: { $0.code == appState.config.targetLanguage })?.name ?? appState.config.targetLanguage
                        Text("Translation active — output in \(langName)")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                        Spacer()
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.06))
                    )
                }

                // Transcript list section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(sectionHeaderText)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .tracking(0.5)
                        Spacer()
                    }

                    if appState.database.transcripts.isEmpty {
                        EmptyTranscriptsView(hotkeyDescription: appState.hotkeyDescription)
                    } else {
                        LazyVStack(spacing: 1) {
                            ForEach(appState.database.transcripts.prefix(50)) { transcript in
                                TranscriptRow(transcript: transcript)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sectionHeaderText: String {
        let today = appState.database.transcripts.filter {
            Calendar.current.isDateInToday($0.timestamp)
        }.count
        if today > 0 { return "TODAY (\(today))" }
        return "RECENT"
    }

    private func formatNumber(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }

    private func formatTimeSaved(_ seconds: Double) -> String {
        // Estimate typing time saved: ~40 WPM typing vs speaking
        let minutesSaved = seconds / 60.0 * 1.5 // rough multiplier
        if minutesSaved < 1 { return "0m" }
        if minutesSaved < 60 { return "\(Int(minutesSaved))m" }
        return String(format: "%.1fh", minutesSaved / 60.0)
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color.opacity(0.8))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

// MARK: - Quick Action Banner

private struct QuickActionBanner: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hold \(appState.hotkeyDescription) to dictate")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                Text("Smart formatting and context awareness handle the rest.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Animated mic icon
            ZStack {
                Circle()
                    .fill(appState.isRecording ?
                          Color.red.opacity(0.15) :
                          Color.accentColor.opacity(0.1))
                    .frame(width: 44, height: 44)

                Image(systemName: appState.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 18))
                    .foregroundColor(appState.isRecording ? .red : .accentColor)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Empty State

private struct EmptyTranscriptsView: View {
    let hotkeyDescription: String

    var body: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 20)
            Image(systemName: "waveform")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No transcripts yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            Text("Hold \(hotkeyDescription) to start dictating.\nTranscripts will appear here.")
                .font(.system(size: 12))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Transcript Row

private struct TranscriptRow: View {
    let transcript: Transcript
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Time column
            VStack(spacing: 2) {
                Text(timeString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                Text(durationString)
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
            .frame(width: 60, alignment: .trailing)

            // Divider dot
            Circle()
                .fill(Color.accentColor.opacity(0.3))
                .frame(width: 5, height: 5)
                .padding(.top, 5)

            // Content
            Text(transcript.cleanedText)
                .font(.system(size: 13))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Copy button
            if isHovered {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcript.cleanedText, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: transcript.timestamp)
    }

    private var durationString: String {
        let seconds = Int(transcript.durationSeconds)
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}
