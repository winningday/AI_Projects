import Foundation

/// Tracks user corrections to enable self-learning.
/// On iOS, this is used by the keyboard extension to detect when the user edits
/// the text that was just inserted via voice transcription.
final class CorrectionTracker {
    private let config: SharedConfig
    private let database: TranscriptDatabase

    init(config: SharedConfig = .shared, database: TranscriptDatabase = .shared) {
        self.config = config
        self.database = database
    }

    /// Process corrections by comparing the injected text with what the user edited it to.
    /// Called by the keyboard extension when it detects the user modified the inserted text.
    func processCorrections(
        injectedText: String,
        editedText: String,
        transcript: Transcript
    ) {
        guard injectedText != editedText else { return }

        // Store the corrected text on the transcript
        try? database.updateCorrectedText(editedText, for: transcript)

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

    /// Compares two strings word-by-word and extracts in-place replacements.
    func extractWordCorrections(original: String, corrected: String) -> [WordCorrection] {
        let originalWords = tokenize(original)
        let correctedWords = tokenize(corrected)
        var corrections: [WordCorrection] = []

        let lcs = longestCommonSubsequence(originalWords, correctedWords)

        var oi = 0, ci = 0, li = 0

        while oi < originalWords.count && ci < correctedWords.count {
            if li < lcs.count && originalWords[oi].lowercased() == lcs[li].lowercased()
                && correctedWords[ci].lowercased() == lcs[li].lowercased() {
                oi += 1; ci += 1; li += 1
            } else if li < lcs.count && correctedWords[ci].lowercased() == lcs[li].lowercased() {
                oi += 1
            } else if li < lcs.count && originalWords[oi].lowercased() == lcs[li].lowercased() {
                ci += 1
            } else {
                let orig = originalWords[oi]
                let corr = correctedWords[ci]
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
        text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    private func isCorrectionCandidate(original: String, corrected: String) -> Bool {
        let o = original.lowercased().trimmingCharacters(in: .punctuationCharacters)
        let c = corrected.lowercased().trimmingCharacters(in: .punctuationCharacters)

        guard !o.isEmpty, !c.isEmpty else { return false }
        if o == c { return true }

        let maxLen = max(o.count, c.count)
        guard maxLen > 0 else { return false }

        let distance = levenshteinDistance(o, c)
        let similarity = 1.0 - (Double(distance) / Double(maxLen))

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
