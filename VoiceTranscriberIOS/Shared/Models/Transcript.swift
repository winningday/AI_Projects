import Foundation

/// Represents a single voice transcription entry with original, cleaned, and user-corrected text.
struct Transcript: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let originalText: String
    let cleanedText: String
    let durationSeconds: Double
    /// The user's corrected version of cleanedText, captured by CorrectionTracker.
    /// nil if the user made no changes after injection.
    var correctedText: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        originalText: String,
        cleanedText: String,
        durationSeconds: Double,
        correctedText: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.originalText = originalText
        self.cleanedText = cleanedText
        self.durationSeconds = durationSeconds
        self.correctedText = correctedText
    }

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}
