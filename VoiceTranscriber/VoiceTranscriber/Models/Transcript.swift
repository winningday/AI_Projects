import Foundation

/// Represents a single voice transcription entry with original and cleaned text.
struct Transcript: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let originalText: String
    let cleanedText: String
    let durationSeconds: Double

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        originalText: String,
        cleanedText: String,
        durationSeconds: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.originalText = originalText
        self.cleanedText = cleanedText
        self.durationSeconds = durationSeconds
    }

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}
