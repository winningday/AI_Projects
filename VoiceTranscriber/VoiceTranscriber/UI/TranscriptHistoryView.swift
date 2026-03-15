import SwiftUI

/// Displays a searchable list of all past transcriptions with a detail pane.
struct TranscriptHistoryView: View {
    @ObservedObject var database: TranscriptDatabase
    @State private var searchText = ""
    @State private var selectedTranscript: Transcript?
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField("Search transcripts...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                if filteredTranscripts.isEmpty {
                    emptyState
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
                                    if selectedTranscript?.id == transcript.id {
                                        selectedTranscript = nil
                                    }
                                }
                            }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 260)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 4) {
                        Text("\(filteredTranscripts.count)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))

                        Button(action: { showDeleteConfirmation = true }) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                        }
                        .disabled(database.transcripts.isEmpty)
                        .help("Clear all transcripts")
                    }
                }
            }
        } detail: {
            if let transcript = selectedTranscript {
                TranscriptDetailView(transcript: transcript)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 44))
                        .foregroundStyle(.linearGradient(
                            colors: [.blue.opacity(0.4), .purple.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    Text("Select a transcript to view details")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(minWidth: 650, minHeight: 420)
        .alert("Clear All Transcripts", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                try? database.deleteAll()
                selectedTranscript = nil
            }
        } message: {
            Text("This will permanently delete all transcript history. This cannot be undone.")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: searchText.isEmpty ? "waveform.badge.plus" : "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.linearGradient(
                    colors: [.blue.opacity(0.5), .purple.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            Text(searchText.isEmpty ? "No transcripts yet" : "No matching transcripts")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)

            if searchText.isEmpty {
                Text("Press your hotkey to start recording.\nTranscripts will appear here.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

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
        VStack(alignment: .leading, spacing: 6) {
            Text(transcript.cleanedText)
                .font(.system(size: 13))
                .lineLimit(2)

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 9))
                Text(transcript.formattedTimestamp)
                    .font(.system(size: 11))

                Spacer()

                Image(systemName: "timer")
                    .font(.system(size: 9))
                Text(formattedDuration)
                    .font(.system(size: 11))
            }
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var formattedDuration: String {
        let seconds = Int(transcript.durationSeconds)
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}

// MARK: - Detail View

struct TranscriptDetailView: View {
    let transcript: Transcript
    @State private var copiedField: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(transcript.formattedTimestamp)
                            .font(.system(size: 18, weight: .semibold))
                        HStack(spacing: 12) {
                            Label(
                                String(format: "%.1fs", transcript.durationSeconds),
                                systemImage: "timer"
                            )
                            Label(
                                "\(transcript.cleanedText.split(separator: " ").count) words",
                                systemImage: "textformat.abc"
                            )
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                // Cleaned text card
                TextCard(
                    title: "Cleaned Text",
                    icon: "sparkles",
                    iconColor: .purple,
                    text: transcript.cleanedText,
                    isCopied: copiedField == "cleaned",
                    onCopy: {
                        copyToClipboard(transcript.cleanedText)
                        copiedField = "cleaned"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedField = nil }
                    }
                )

                // Original text card
                TextCard(
                    title: "Original Transcription",
                    icon: "waveform",
                    iconColor: .blue,
                    text: transcript.originalText,
                    isSecondary: true,
                    isCopied: copiedField == "original",
                    onCopy: {
                        copyToClipboard(transcript.originalText)
                        copiedField = "original"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedField = nil }
                    }
                )
            }
            .padding(24)
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Text Card

private struct TextCard: View {
    let title: String
    let icon: String
    let iconColor: Color
    let text: String
    var isSecondary: Bool = false
    var isCopied: Bool = false
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: onCopy) {
                    HStack(spacing: 3) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Copied!" : "Copy")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(isCopied ? .green : .accentColor)
                }
                .buttonStyle(.plain)
            }

            Text(text)
                .font(.system(size: 14))
                .foregroundColor(isSecondary ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }
}
