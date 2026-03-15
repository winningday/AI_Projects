import SwiftUI

/// Home tab showing welcome banner, stats, and recent transcript history.
struct HomeView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with stats
                HStack {
                    Text("Welcome back")
                        .font(.system(size: 26, weight: .bold))

                    Spacer()

                    HStack(spacing: 16) {
                        StatBadge(icon: "text.word.spacing", value: formatWords(appState.totalWordsTranscribed), label: "words")
                        StatBadge(icon: "number", value: "\(appState.database.transcripts.count)", label: "transcripts")
                    }
                }

                // Hero banner
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.linearGradient(
                            colors: [Color(nsColor: .controlAccentColor).opacity(0.8), .purple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(height: 140)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Text("Hold")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                            Text("fn")
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                .italic()
                            Text("to dictate and let VoiceTranscriber format for you")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .lineLimit(2)

                        Text("Press and hold \(appState.hotkeyDescription) to dictate in any app. Smart Formatting and context awareness handle the rest.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(2)
                    }
                    .padding(24)
                }

                // Error banner
                if let error = appState.lastError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Spacer()
                        Button(action: { appState.lastError = nil }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.08))
                    )
                }

                // Today's transcripts header
                HStack {
                    Text(todayHeaderText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                    Spacer()
                }

                // Transcript list
                if appState.database.transcripts.isEmpty {
                    VStack(spacing: 16) {
                        Spacer().frame(height: 20)
                        Image(systemName: "waveform.badge.plus")
                            .font(.system(size: 36))
                            .foregroundStyle(.linearGradient(
                                colors: [.blue.opacity(0.4), .purple.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                        Text("No transcripts yet")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Press your hotkey to start recording.\nTranscripts will appear here.")
                            .font(.system(size: 12))
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(appState.database.transcripts.prefix(50)) { transcript in
                            TranscriptRow(transcript: transcript)
                        }
                    }
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var todayHeaderText: String {
        let today = appState.database.transcripts.filter {
            Calendar.current.isDateInToday($0.timestamp)
        }.count
        if today > 0 { return "TODAY (\(today))" }
        return "RECENT"
    }

    private func formatWords(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}

// MARK: - Stat Badge

private struct StatBadge: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

// MARK: - Transcript Row

private struct TranscriptRow: View {
    let transcript: Transcript
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Timestamp
            Text(timeString)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 65, alignment: .trailing)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(transcript.cleanedText)
                    .font(.system(size: 13))
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Copy button (visible on hover)
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
            RoundedRectangle(cornerRadius: 8)
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
}
