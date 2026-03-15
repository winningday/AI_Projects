import SwiftUI

/// Productivity dashboard showing voice dictation speed vs typing comparison.
struct StatsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Productivity")
                    .font(.system(size: 26, weight: .bold))

                // Speed comparison hero card
                SpeedComparisonCard(appState: appState)

                // Metric cards row
                HStack(spacing: 12) {
                    MetricCard(
                        title: "Voice WPM",
                        value: appState.wordsPerMinute > 0 ? "\(appState.wordsPerMinute)" : "—",
                        subtitle: "words per minute dictating",
                        icon: "mic.fill",
                        color: .blue
                    )
                    MetricCard(
                        title: "Typing WPM",
                        value: "\(appState.config.typingSpeed)",
                        subtitle: "your baseline typing speed",
                        icon: "keyboard",
                        color: .gray
                    )
                    MetricCard(
                        title: "Time Saved",
                        value: formatMinutes(appState.minutesSaved),
                        subtitle: "vs typing the same text",
                        icon: "clock.badge.checkmark",
                        color: .green
                    )
                }

                // Weekly activity
                WeeklyActivityCard(data: appState.weeklyWordCounts)

                // Session breakdown
                HStack(spacing: 12) {
                    MetricCard(
                        title: "Total Words",
                        value: formatNumber(appState.totalWordsTranscribed),
                        subtitle: "across all transcripts",
                        icon: "character.cursor.ibeam",
                        color: .purple
                    )
                    MetricCard(
                        title: "Transcripts",
                        value: "\(appState.database.transcripts.count)",
                        subtitle: "\(appState.todayTranscriptCount) today",
                        icon: "doc.text",
                        color: .indigo
                    )
                    MetricCard(
                        title: "Avg Length",
                        value: "\(appState.averageWordsPerTranscript)",
                        subtitle: "words per transcript",
                        icon: "text.alignleft",
                        color: .teal
                    )
                }

                // Recording time
                HStack(spacing: 12) {
                    MetricCard(
                        title: "Recording Time",
                        value: formatDuration(appState.totalRecordingSeconds),
                        subtitle: "total time speaking",
                        icon: "waveform",
                        color: .red
                    )
                    MetricCard(
                        title: "Today",
                        value: formatNumber(appState.todayWordCount),
                        subtitle: "words dictated today",
                        icon: "calendar",
                        color: .orange
                    )
                    // Typing speed config hint
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.8))
                            Text("Typing Speed")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        Text("\(appState.config.typingSpeed) WPM")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Change in Settings")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func formatNumber(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }

    private func formatMinutes(_ minutes: Double) -> String {
        if minutes < 1 { return "< 1m" }
        if minutes < 60 { return "\(Int(minutes))m" }
        return String(format: "%.1fh", minutes / 60.0)
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        return String(format: "%.1fh", seconds / 3600.0)
    }
}

// MARK: - Speed Comparison Hero Card

private struct SpeedComparisonCard: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            if appState.wordsPerMinute > 0 {
                // Has data — show comparison
                HStack(spacing: 0) {
                    // Typing bar
                    VStack(spacing: 6) {
                        Text("TYPING")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                            .tracking(1)
                        Text("\(appState.config.typingSpeed)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                        Text("WPM")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    // Speed multiplier badge
                    VStack(spacing: 4) {
                        Text(String(format: "%.1fx", appState.speedMultiplier))
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .foregroundStyle(.linearGradient(
                                colors: speedGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                        Text(speedLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(speedColor)
                    }
                    .frame(maxWidth: .infinity)

                    // Voice bar
                    VStack(spacing: 6) {
                        Text("VOICE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.blue)
                            .tracking(1)
                        Text("\(appState.wordsPerMinute)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.blue)
                        Text("WPM")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blue.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                }

                // Progress bar comparison
                GeometryReader { geo in
                    let maxWPM = max(Double(appState.wordsPerMinute), Double(appState.config.typingSpeed))
                    let typingWidth = maxWPM > 0 ? (Double(appState.config.typingSpeed) / maxWPM) * geo.size.width : 0
                    let voiceWidth = maxWPM > 0 ? (Double(appState.wordsPerMinute) / maxWPM) * geo.size.width : 0

                    VStack(spacing: 6) {
                        // Typing bar
                        HStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: typingWidth, height: 8)
                            Spacer(minLength: 0)
                        }
                        // Voice bar
                        HStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.linearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                                .frame(width: voiceWidth, height: 8)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(height: 22)
                .padding(.horizontal, 20)

            } else {
                // No data yet
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis.ascending")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("Start dictating to see your speed comparison")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("Your voice WPM will be compared against your typing speed (\(appState.config.typingSpeed) WPM)")
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                }
                .padding(.vertical, 8)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                )
        )
    }

    private var speedColor: Color {
        if appState.speedMultiplier >= 2.0 { return .green }
        if appState.speedMultiplier >= 1.5 { return .blue }
        if appState.speedMultiplier >= 1.0 { return .orange }
        return .red
    }

    private var speedGradient: [Color] {
        if appState.speedMultiplier >= 2.0 { return [.green, .mint] }
        if appState.speedMultiplier >= 1.5 { return [.blue, .cyan] }
        if appState.speedMultiplier >= 1.0 { return [.orange, .yellow] }
        return [.red, .orange]
    }

    private var speedLabel: String {
        if appState.speedMultiplier >= 2.0 { return "FASTER" }
        if appState.speedMultiplier >= 1.0 { return "faster" }
        return "slower"
    }
}

// MARK: - Weekly Activity Card

private struct WeeklyActivityCard: View {
    let data: [(date: Date, words: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.blue.opacity(0.8))
                Text("Last 7 Days")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                let total = data.reduce(0) { $0 + $1.words }
                Text("\(total) words")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }

            // Bar chart
            let maxWords = max(data.map(\.words).max() ?? 1, 1)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                    VStack(spacing: 4) {
                        if item.words > 0 {
                            Text("\(item.words)")
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }

                        RoundedRectangle(cornerRadius: 4)
                            .fill(barColor(for: item))
                            .frame(height: max(4, CGFloat(item.words) / CGFloat(maxWords) * 80))

                        Text(dayLabel(item.date))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 110)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func barColor(for item: (date: Date, words: Int)) -> Color {
        if Calendar.current.isDateInToday(item.date) {
            return .blue
        }
        return item.words > 0 ? .blue.opacity(0.4) : .secondary.opacity(0.15)
    }

    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

// MARK: - Metric Card

private struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
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

            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
