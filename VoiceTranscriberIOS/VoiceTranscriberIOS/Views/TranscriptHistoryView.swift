import SwiftUI

struct TranscriptHistoryView: View {
    @ObservedObject var appState: AppState
    @State private var searchText = ""
    @State private var searchResults: [Transcript]?

    private var displayedTranscripts: [Transcript] {
        searchResults ?? appState.database.transcripts
    }

    var body: some View {
        NavigationView {
            Group {
                if displayedTranscripts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "waveform")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(searchText.isEmpty ? "No transcriptions yet" : "No results found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        if searchText.isEmpty {
                            Text("Use the mic button or keyboard to start transcribing.")
                                .font(.subheadline)
                                .foregroundColor(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding()
                } else {
                    List {
                        ForEach(displayedTranscripts) { transcript in
                            TranscriptRow(transcript: transcript) {
                                UIPasteboard.general.string = transcript.cleanedText
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let transcript = displayedTranscripts[index]
                                try? appState.database.delete(transcript)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("History")
            .searchable(text: $searchText, prompt: "Search transcriptions")
            .onChange(of: searchText) { newValue in
                if newValue.isEmpty {
                    searchResults = nil
                } else {
                    searchResults = try? appState.database.search(query: newValue)
                }
            }
            .toolbar {
                if !appState.database.transcripts.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        EditButton()
                    }
                }
            }
        }
    }
}

// MARK: - Transcript Row

struct TranscriptRow: View {
    let transcript: Transcript
    let onCopy: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cleaned text
            Text(transcript.cleanedText)
                .font(.body)
                .lineLimit(isExpanded ? nil : 3)
                .onTapGesture {
                    withAnimation { isExpanded.toggle() }
                }

            // If user corrected
            if let corrected = transcript.correctedText, corrected != transcript.cleanedText {
                HStack(spacing: 4) {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Corrected")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            // Metadata row
            HStack {
                Text(transcript.formattedTimestamp)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(transcript.cleanedText.split(separator: " ").count) words")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(formatDuration(transcript.durationSeconds))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Button {
                    onCopy()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }

            // Expandable: show original text
            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Original")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Text(transcript.originalText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ duration: Double) -> String {
        let seconds = Int(duration)
        if seconds < 60 {
            return "\(seconds)s"
        }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}
