import Foundation

/// Tracks user corrections after text injection to enable self-learning.
///
/// Flow:
/// 1. After text is injected, `startTracking()` takes an immediate snapshot of the field
/// 2. After a delay (default 5s), reads the field again
/// 3. Computes word-level diff to detect corrections
/// 4. Auto-adds corrected words to the dictionary
/// 5. Stores correction pairs (wrong → right) for future Claude prompts
/// 6. Updates the transcript's correctedText field
@MainActor
final class CorrectionTracker {
    /// How long to wait before checking for corrections (seconds)
    private let checkDelay: TimeInterval = 5.0

    private let config: ConfigManager
    private let database: TranscriptDatabase

    /// Currently pending correction check
    private var pendingTask: Task<Void, Never>?

    init(config: ConfigManager, database: TranscriptDatabase) {
        self.config = config
        self.database = database
    }

    /// Begin tracking corrections for the given transcript.
    /// Takes an immediate snapshot of the text field, then schedules a delayed re-read.
    func startTracking(transcript: Transcript, injectedText: String) {
        // Cancel any previous pending check
        pendingTask?.cancel()

        // Small delay to let the paste complete, then snapshot
        pendingTask = Task {
            // Wait 150ms for paste to settle
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }

            let postInjectionSnapshot = TextInjector.readFullTextFromActiveField()

            // Wait for user to review and potentially edit
            try? await Task.sleep(nanoseconds: UInt64(checkDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }

            let afterEditSnapshot = TextInjector.readFullTextFromActiveField()

            // Process the diff
            guard let before = postInjectionSnapshot, let after = afterEditSnapshot else { return }
            guard before != after else { return } // No changes

            processCorrections(
                injectedText: injectedText,
                fieldBefore: before,
                fieldAfter: after,
                transcript: transcript
            )
        }
    }

    /// Cancel any pending correction check (e.g., if user starts a new recording)
    func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
    }

    // MARK: - Diff Detection

    private func processCorrections(
        injectedText: String,
        fieldBefore: String,
        fieldAfter: String,
        transcript: Transcript
    ) {
        // Find the injected text within the field snapshot
        guard let injectedRange = fieldBefore.range(of: injectedText) else { return }

        // Extract the same region from the edited field
        let startOffset = fieldBefore.distance(from: fieldBefore.startIndex, to: injectedRange.lowerBound)
        let endOffset = fieldBefore.distance(from: fieldBefore.startIndex, to: injectedRange.upperBound)

        // The after text might be shorter/longer due to edits
        let afterStart = afterEditStart(in: fieldAfter, offset: startOffset)
        guard let afterStart else { return }

        // Estimate where the edited region ends by accounting for length changes
        let lengthDelta = fieldAfter.count - fieldBefore.count
        let estimatedEndOffset = endOffset + lengthDelta
        let afterEnd = min(estimatedEndOffset, fieldAfter.count)
        guard afterEnd > afterStart else { return }

        let afterStartIdx = fieldAfter.index(fieldAfter.startIndex, offsetBy: afterStart)
        let afterEndIdx = fieldAfter.index(fieldAfter.startIndex, offsetBy: afterEnd)
        let editedText = String(fieldAfter[afterStartIdx..<afterEndIdx])

        // Store the corrected text on the transcript
        if editedText != injectedText {
            try? database.updateCorrectedText(editedText, for: transcript)
        }

        // Word-level diff to find specific corrections
        let corrections = extractWordCorrections(original: injectedText, corrected: editedText)
        guard !corrections.isEmpty else { return }

        // Auto-add corrected words to dictionary (if enabled)
        if config.autoAddToDictionary {
            for correction in corrections {
                config.addDictionaryWord(correction.corrected, autoAdded: true)
            }
        }

        // Store correction pairs for future Claude context
        config.addCorrections(corrections)
    }

    private func afterEditStart(in text: String, offset: Int) -> Int? {
        guard offset >= 0, offset <= text.count else { return nil }
        return offset
    }

    /// Compares two strings word-by-word and extracts in-place replacements.
    /// Only detects word substitutions (corrections), not additions or deletions.
    func extractWordCorrections(original: String, corrected: String) -> [WordCorrection] {
        let originalWords = tokenize(original)
        let correctedWords = tokenize(corrected)
        var corrections: [WordCorrection] = []

        // Use longest common subsequence to align words
        let lcs = longestCommonSubsequence(originalWords, correctedWords)

        var oi = 0, ci = 0, li = 0

        while oi < originalWords.count && ci < correctedWords.count {
            if li < lcs.count && originalWords[oi].lowercased() == lcs[li].lowercased()
                && correctedWords[ci].lowercased() == lcs[li].lowercased() {
                // Both match LCS — no change
                oi += 1; ci += 1; li += 1
            } else if li < lcs.count && correctedWords[ci].lowercased() == lcs[li].lowercased() {
                // Original word was deleted (user removed it) — skip
                oi += 1
            } else if li < lcs.count && originalWords[oi].lowercased() == lcs[li].lowercased() {
                // Word was inserted in corrected — skip (new content, not a correction)
                ci += 1
            } else {
                // Both differ from LCS — this is a substitution (correction)
                let orig = originalWords[oi]
                let corr = correctedWords[ci]
                // Only count as correction if words are somewhat similar (not completely different content)
                if isCorrectionCandidate(original: orig, corrected: corr) {
                    corrections.append(WordCorrection(original: orig, corrected: corr, date: Date()))
                }
                oi += 1; ci += 1
            }
        }

        return corrections
    }

    // MARK: - Helpers

    private func tokenize(_ text: String) -> [String] {
        // Split on whitespace, preserving punctuation attached to words
        text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    /// Determines if a word change looks like a spelling/transcription correction
    /// vs completely different content.
    private func isCorrectionCandidate(original: String, corrected: String) -> Bool {
        let o = original.lowercased().trimmingCharacters(in: .punctuationCharacters)
        let c = corrected.lowercased().trimmingCharacters(in: .punctuationCharacters)

        guard !o.isEmpty, !c.isEmpty else { return false }

        // Same word with different casing/punctuation — still a correction
        if o == c { return true }

        // Check string similarity (Levenshtein-like)
        let maxLen = max(o.count, c.count)
        guard maxLen > 0 else { return false }

        let distance = levenshteinDistance(o, c)
        let similarity = 1.0 - (Double(distance) / Double(maxLen))

        // Words with > 40% similarity are likely corrections (not unrelated substitutions)
        return similarity > 0.4
    }

    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count, n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j-1] + 1, prev[j-1] + cost)
            }
            prev = curr
        }

        return prev[n]
    }

    private func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        let m = a.count, n = b.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...m {
            for j in 1...n {
                if a[i-1].lowercased() == b[j-1].lowercased() {
                    dp[i][j] = dp[i-1][j-1] + 1
                } else {
                    dp[i][j] = max(dp[i-1][j], dp[i][j-1])
                }
            }
        }

        // Backtrack
        var result: [String] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i-1].lowercased() == b[j-1].lowercased() {
                result.append(a[i-1])
                i -= 1; j -= 1
            } else if dp[i-1][j] > dp[i][j-1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return result.reversed()
    }
}

/// A single word-level correction detected from user edits.
struct WordCorrection: Codable, Equatable, Identifiable {
    let id: UUID
    let original: String
    let corrected: String
    let date: Date

    init(id: UUID = UUID(), original: String, corrected: String, date: Date = Date()) {
        self.id = id
        self.original = original
        self.corrected = corrected
        self.date = date
    }
}
