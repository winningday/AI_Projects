import Foundation

/// Fast, deterministic transcript cleanup without any AI/API calls.
/// Handles basic formatting: filler removal, stutter fixing, capitalization, punctuation.
/// Used as the default cleanup mode to avoid Claude hallucination issues.
final class ProgrammaticCleaner {

    private static let fillerWords: Set<String> = [
        "um", "uh", "uhm", "umm", "hmm", "hm", "ah", "er", "erm"
    ]

    /// Cleans a raw transcript using purely programmatic rules.
    /// - Parameter text: Raw transcription from Whisper or Apple Speech
    /// - Parameter styleTone: Optional style tone for formatting adjustments
    /// - Returns: Cleaned text with fillers removed, stutters collapsed, proper capitalization and punctuation
    static func clean(_ text: String, styleTone: StyleTone = .formal) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }

        // Split into words
        var words = result.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

        // Remove standalone filler words
        words = words.filter { word in
            let stripped = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            return !fillerWords.contains(stripped)
        }

        guard !words.isEmpty else { return "" }

        // Collapse immediate word-level repetitions: "I I I think" → "I think"
        var deduped: [String] = []
        for word in words {
            if let last = deduped.last,
               last.lowercased().trimmingCharacters(in: .punctuationCharacters) ==
               word.lowercased().trimmingCharacters(in: .punctuationCharacters) {
                continue
            }
            deduped.append(word)
        }
        words = deduped

        guard !words.isEmpty else { return "" }

        result = words.joined(separator: " ")

        // Apply style-specific formatting
        switch styleTone {
        case .formal, .excited:
            result = capitalizeSentences(result)
        case .casual:
            result = capitalizeSentences(result)
        case .veryCasual:
            result = result.lowercased()
        }

        // Fix standalone "i" → "I" (even in veryCasual, this is standard)
        result = fixLowercaseI(result)

        // Add terminal punctuation based on style
        if let last = result.last {
            switch styleTone {
            case .formal:
                if !".!?".contains(last) {
                    result += "."
                }
            case .casual, .veryCasual:
                // Skip adding periods for casual styles (user preference)
                break
            case .excited:
                if !".!?".contains(last) {
                    result += "!"
                }
            }
        }

        return result
    }

    // MARK: - Helpers

    /// Capitalizes the first letter of each sentence.
    private static func capitalizeSentences(_ text: String) -> String {
        var result = ""
        var capitalizeNext = true

        for char in text {
            if capitalizeNext && char.isLetter {
                result.append(char.uppercased())
                capitalizeNext = false
            } else {
                result.append(char)
            }

            if ".!?".contains(char) {
                capitalizeNext = true
            }
        }

        return result
    }

    /// Fixes standalone lowercase "i" to "I".
    private static func fixLowercaseI(_ text: String) -> String {
        // Match standalone "i" surrounded by word boundaries
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        let fixed = words.map { word -> String in
            let w = String(word)
            // Handle "i" and "i'm", "i'll", "i've", "i'd"
            if w == "i" { return "I" }
            if w.lowercased().hasPrefix("i'") && w.first == "i" {
                return "I" + w.dropFirst()
            }
            return w
        }
        return fixed.joined(separator: " ")
    }
}
