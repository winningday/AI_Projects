import SwiftUI

struct DictionaryView: View {
    @ObservedObject var config: SharedConfig
    @State private var newWord = ""
    @State private var showingAutoAdded = false

    private var filteredEntries: [DictionaryEntry] {
        if showingAutoAdded {
            return config.dictionaryEntries.filter { $0.autoAdded }
        }
        return config.dictionaryEntries
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Add word bar
                HStack {
                    TextField("Add a word or name...", text: $newWord)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit { addWord() }

                    Button {
                        addWord()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()

                // Filter toggle
                Picker("Filter", selection: $showingAutoAdded) {
                    Text("All (\(config.dictionaryEntries.count))").tag(false)
                    Text("Auto-Added (\(config.dictionaryEntries.filter { $0.autoAdded }.count))").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if filteredEntries.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "character.book.closed")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(showingAutoAdded ? "No auto-added words yet" : "Your dictionary is empty")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Add names, technical terms, and custom words to improve transcription accuracy.")
                            .font(.subheadline)
                            .foregroundColor(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(filteredEntries) { entry in
                            HStack {
                                Text(entry.word)
                                    .font(.body)

                                Spacer()

                                if entry.autoAdded {
                                    Text("Auto")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.1))
                                        .cornerRadius(4)
                                }

                                Text(entry.dateAdded, style: .date)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onDelete { offsets in
                            // Map filtered offsets to actual entries
                            let entriesToDelete = offsets.map { filteredEntries[$0] }
                            for entry in entriesToDelete {
                                config.removeDictionaryEntry(entry)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Dictionary")
            .toolbar {
                if !config.dictionaryEntries.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        EditButton()
                    }
                }
            }
        }
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        config.addDictionaryWord(trimmed)
        newWord = ""
    }
}
