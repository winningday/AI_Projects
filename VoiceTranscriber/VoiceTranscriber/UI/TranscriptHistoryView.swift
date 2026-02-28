import SwiftUI

/// Displays a searchable, scrollable list of all past transcriptions.
struct TranscriptHistoryView: View {
    @ObservedObject var database: TranscriptDatabase
    @State private var searchText = ""
    @State private var selectedTranscript: Transcript?
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationSplitView {
            // Sidebar: transcript list
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search transcripts...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // Transcript list
                if filteredTranscripts.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "text.bubble")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text(searchText.isEmpty ? "No transcripts yet" : "No matching transcripts")
                            .foregroundColor(.secondary)
                        if searchText.isEmpty {
                            Text("Press your hotkey to start recording")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List(filteredTranscripts, selection: $selectedTranscript) { transcript in
                        TranscriptRowView(transcript: transcript)
                            .tag(transcript)
                            .contextMenu {
                                Button("Copy Cleaned Text") {
                                    copyToClipboard(transcript.cleanedText)
                                }
                                Button("Copy Original Text") {
                                    copyToClipboard(transcript.originalText)
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    try? database.delete(transcript)
                                }
                            }
                    }
                }
            }
            .frame(minWidth: 250)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { showDeleteConfirmation = true }) {
                        Image(systemName: "trash")
                    }
                    .disabled(database.transcripts.isEmpty)
                    .help("Clear all transcripts")
                }
            }
        } detail: {
            // Detail view
            if let transcript = selectedTranscript {
                TranscriptDetailView(transcript: transcript)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Select a transcript to view details")
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .alert("Clear All Transcripts", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                try? database.deleteAll()
                selectedTranscript = nil
            }
        } message: {
            Text("This will permanently delete all transcript history. This action cannot be undone.")
        }
    }

    private var filteredTranscripts: [Transcript] {
        if searchText.isEmpty {
            return database.transcripts
        }
        let query = searchText.lowercased()
        return database.transcripts.filter {
            $0.originalText.lowercased().contains(query) ||
            $0.cleanedText.lowercased().contains(query)
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Row View

struct TranscriptRowView: View {
    let transcript: Transcript

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(transcript.cleanedText)
                .font(.system(size: 13))
                .lineLimit(2)

            HStack {
                Text(transcript.formattedTimestamp)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formattedDuration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedDuration: String {
        let seconds = Int(transcript.durationSeconds)
        if seconds < 60 {
            return "\(seconds)s"
        }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}

// MARK: - Detail View

struct TranscriptDetailView: View {
    let transcript: Transcript

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(transcript.formattedTimestamp)
                            .font(.headline)
                        Text("Duration: \(String(format: "%.1f", transcript.durationSeconds))s")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                // Cleaned text
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Cleaned Text", systemImage: "sparkles")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Button(action: { copyToClipboard(transcript.cleanedText) }) {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Copy cleaned text")
                        }

                        Text(transcript.cleanedText)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(4)
                }

                // Original text
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Original Transcription", systemImage: "waveform")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Button(action: { copyToClipboard(transcript.originalText) }) {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Copy original text")
                        }

                        Text(transcript.originalText)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(4)
                }
            }
            .padding(20)
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
