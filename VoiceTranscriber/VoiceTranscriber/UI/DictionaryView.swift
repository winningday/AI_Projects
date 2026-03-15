import SwiftUI

/// Dictionary view for managing custom words and names.
struct DictionaryView: View {
    @ObservedObject var config: ConfigManager
    @State private var newWord = ""
    @State private var searchText = ""
    @State private var selectedFilter: DictionaryFilter = .all

    enum DictionaryFilter: String, CaseIterable {
        case all = "All"
        case personal = "Manual"
        case auto = "Auto-added"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Dictionary")
                        .font(.system(size: 26, weight: .bold))
                    Spacer()
                    Button(action: addWord) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Add new")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                // Filter tabs
                HStack(spacing: 16) {
                    ForEach(DictionaryFilter.allCases, id: \.self) { filter in
                        Button(action: { selectedFilter = filter }) {
                            Text(filter.rawValue)
                                .font(.system(size: 13, weight: selectedFilter == filter ? .semibold : .regular))
                                .foregroundColor(selectedFilter == filter ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) {
                            if selectedFilter == filter {
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(height: 2)
                                    .offset(y: 6)
                            }
                        }
                    }
                    Spacer()

                    // Search
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        TextField("Search...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .frame(width: 120)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
            }
            .padding(28)
            .padding(.bottom, 0)

            // Info banner
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.linearGradient(
                        colors: [Color(nsColor: .controlAccentColor).opacity(0.7), .purple.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                VStack(alignment: .leading, spacing: 6) {
                    Text("VoiceTranscriber speaks the way you speak.")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Add personal terms, company jargon, client names, or industry-specific lingo. These words are sent to the transcription engine to improve accuracy.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(3)

                    // Sample chips
                    HStack(spacing: 6) {
                        AddWordChip(label: "Add new word", action: { /* focus field */ })
                        ForEach(config.dictionaryEntries.prefix(4)) { entry in
                            WordChip(label: entry.word)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .frame(height: 130)
            .padding(.horizontal, 28)

            // Add word field
            HStack(spacing: 8) {
                TextField("Type a word or name to add...", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onSubmit { addWord() }

                Button("Add") { addWord() }
                    .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 12)

            Divider()

            // Word list
            if filteredEntries.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(config.dictionaryEntries.isEmpty ? "No words added yet" : "No matching words")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(filteredEntries) { entry in
                        HStack {
                            Text(entry.word)
                                .font(.system(size: 14))
                            if entry.autoAdded {
                                Text("auto")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        Capsule().fill(Color(nsColor: .controlBackgroundColor))
                                    )
                            }
                            Spacer()
                            Button(action: { config.removeDictionaryEntry(entry) }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Helpers

    private var filteredEntries: [DictionaryEntry] {
        var entries = config.dictionaryEntries

        switch selectedFilter {
        case .all: break
        case .personal: entries = entries.filter { !$0.autoAdded }
        case .auto: entries = entries.filter { $0.autoAdded }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            entries = entries.filter { $0.word.lowercased().contains(query) }
        }

        return entries
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        config.addDictionaryWord(trimmed)
        newWord = ""
    }
}

// MARK: - Chips

private struct WordChip: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
            )
    }
}

private struct AddWordChip: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
    }
}
