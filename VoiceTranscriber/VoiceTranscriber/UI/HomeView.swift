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
                        title: "Speed",
                        value: appState.speedMultiplier > 0 ? String(format: "%.1fx", appState.speedMultiplier) : "—",
                        icon: "bolt.fill",
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
                    if appState.database.transcripts.isEmpty {
                        EmptyTranscriptsView(hotkeyDescription: appState.hotkeyDescription)
                    } else {
                        ForEach(groupedTranscripts, id: \.key) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(group.key.uppercased())
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .tracking(0.5)
                                    Text("(\(group.transcripts.count))")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                                    Spacer()
                                }
                                .padding(.top, 8)

                                LazyVStack(spacing: 1) {
                                    ForEach(group.transcripts) { transcript in
                                        TranscriptRow(transcript: transcript, showDate: !isRecentDate(group.key))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var groupedTranscripts: [(key: String, transcripts: [Transcript])] {
        let calendar = Calendar.current
        let dateFmt = DateFormatter()
        dateFmt.dateStyle = .medium

        let recent = Array(appState.database.transcripts.prefix(50))
        let grouped = Dictionary(grouping: recent) { transcript -> String in
            if calendar.isDateInToday(transcript.timestamp) { return "Today" }
            if calendar.isDateInYesterday(transcript.timestamp) { return "Yesterday" }
            return dateFmt.string(from: transcript.timestamp)
        }

        // Sort: Today first, Yesterday second, then by most recent date
        return grouped.sorted { a, b in
            let order = ["Today": 0, "Yesterday": 1]
            let aOrder = order[a.key] ?? 2
            let bOrder = order[b.key] ?? 2
            if aOrder != bOrder { return aOrder < bOrder }
            let aDate = a.value.first?.timestamp ?? .distantPast
            let bDate = b.value.first?.timestamp ?? .distantPast
            return aDate > bDate
        }
    }

    private func isRecentDate(_ key: String) -> Bool {
        key == "Today" || key == "Yesterday"
    }

    private func formatNumber(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }

    private func formatMinutes(_ minutes: Double) -> String {
        if minutes < 1 { return "0m" }
        if minutes < 60 { return "\(Int(minutes))m" }
        return String(format: "%.1fh", minutes / 60.0)
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
    var showDate: Bool = false
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
            .frame(width: showDate ? 110 : 60, alignment: .trailing)

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
        if showDate {
            formatter.dateFormat = "MMM d, h:mm a"
        } else {
            formatter.dateFormat = "h:mm a"
        }
        return formatter.string(from: transcript.timestamp)
    }

    private var durationString: String {
        let seconds = Int(transcript.durationSeconds)
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}
