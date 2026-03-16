import SwiftUI

struct StatsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Main Stats Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        StatCard(
                            title: "Total Words",
                            value: "\(appState.totalWordsTranscribed)",
                            icon: "text.word.spacing",
                            color: .blue
                        )
                        StatCard(
                            title: "Voice WPM",
                            value: "\(appState.wordsPerMinute)",
                            icon: "speedometer",
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
                            value: appState.speedMultiplier > 0 ? String(format: "%.1fx", appState.speedMultiplier) : "--",
                            icon: "bolt.fill",
                            color: .orange
                        )
                    }

                    // Time Saved
                    if appState.minutesSaved > 0 {
                        HStack {
                            Image(systemName: "clock.badge.checkmark")
                                .font(.title2)
                                .foregroundColor(.green)
                            VStack(alignment: .leading) {
                                Text("Time Saved")
                                    .font(.headline)
                                Text(formatTimeSaved(appState.minutesSaved))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color.green.opacity(0.08))
                        .cornerRadius(12)
                    }

                    // Weekly Activity
                    WeeklyActivityCard(weeklyData: appState.weeklyWordCounts)

                    // Dictionary & Corrections Stats
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Learning")
                            .font(.headline)

                        HStack(spacing: 16) {
                            StatMiniCard(
                                title: "Dictionary",
                                value: "\(appState.config.dictionaryEntries.count)"
                            )
                            StatMiniCard(
                                title: "Corrections",
                                value: "\(appState.config.corrections.count)"
                            )
                            StatMiniCard(
                                title: "Auto-Added",
                                value: "\(appState.config.dictionaryEntries.filter { $0.autoAdded }.count)"
                            )
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Stats")
        }
    }

    private func formatTimeSaved(_ minutes: Double) -> String {
        if minutes < 1 {
            return "\(Int(minutes * 60)) seconds saved vs typing"
        } else if minutes < 60 {
            return String(format: "%.1f minutes saved vs typing", minutes)
        } else {
            return String(format: "%.1f hours saved vs typing", minutes / 60)
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }

            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .monospacedDigit()

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Weekly Activity Card

struct WeeklyActivityCard: View {
    let weeklyData: [(date: Date, words: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .font(.headline)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(weeklyData.enumerated()), id: \.offset) { _, entry in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(entry.words > 0 ? Color.blue : Color(.tertiarySystemGroupedBackground))
                            .frame(height: barHeight(for: entry.words))

                        Text(dayLabel(entry.date))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func barHeight(for words: Int) -> CGFloat {
        let maxWords = max(weeklyData.map(\.words).max() ?? 1, 1)
        if words == 0 { return 4 }
        return max(8, CGFloat(words) / CGFloat(maxWords) * 80)
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return String(formatter.string(from: date).prefix(2))
    }
}
