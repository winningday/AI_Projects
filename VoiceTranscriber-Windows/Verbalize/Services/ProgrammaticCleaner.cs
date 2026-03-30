// Module: Fast deterministic transcript cleanup without AI/API calls
using Verbalize.Models;

namespace Verbalize.Services;

/// <summary>
/// Fast, deterministic transcript cleanup without any AI/API calls.
/// Handles basic formatting: filler removal, stutter fixing, capitalization, punctuation.
/// Used as the default cleanup mode to avoid Claude hallucination issues.
/// </summary>
public static class ProgrammaticCleaner
{
    private static readonly HashSet<string> FillerWords = new(StringComparer.OrdinalIgnoreCase)
    {
        "um", "uh", "uhm", "umm", "hmm", "hm", "ah", "er", "erm"
    };

    /// <summary>
    /// Cleans a raw transcript using purely programmatic rules.
    /// </summary>
    public static string Clean(string text, StyleTone tone = StyleTone.Formal)
    {
        var result = text.Trim();
        if (string.IsNullOrEmpty(result)) return result;

        // Split into words
        var words = result.Split(' ', StringSplitOptions.RemoveEmptyEntries).ToList();

        // Remove standalone filler words
        words = words.Where(w =>
        {
            var stripped = w.Trim('.', ',', '!', '?', ';', ':').ToLowerInvariant();
            return !FillerWords.Contains(stripped);
        }).ToList();

        if (words.Count == 0) return "";

        // Collapse immediate word-level repetitions: "I I I think" → "I think"
        var deduped = new List<string>();
        foreach (var word in words)
        {
            if (deduped.Count > 0 &&
                deduped[^1].Trim('.', ',', '!', '?').Equals(
                    word.Trim('.', ',', '!', '?'), StringComparison.OrdinalIgnoreCase))
                continue;
            deduped.Add(word);
        }
        words = deduped;

        if (words.Count == 0) return "";

        result = string.Join(' ', words);

        // Apply style-specific formatting
        switch (tone)
        {
            case StyleTone.Formal:
            case StyleTone.Excited:
            case StyleTone.Casual:
                result = CapitalizeSentences(result);
                break;
            case StyleTone.VeryCasual:
                result = result.ToLowerInvariant();
                break;
        }

        // Fix standalone "i" → "I"
        result = FixLowercaseI(result);

        // Add terminal punctuation based on style
        if (result.Length > 0)
        {
            var last = result[^1];
            switch (tone)
            {
                case StyleTone.Formal:
                    if (last != '.' && last != '!' && last != '?')
                        result += ".";
                    break;
                case StyleTone.Excited:
                    if (last != '.' && last != '!' && last != '?')
                        result += "!";
                    break;
                // Casual and VeryCasual: skip adding periods
            }
        }

        return result;
    }

    private static string CapitalizeSentences(string text)
    {
        var chars = text.ToCharArray();
        var capitalizeNext = true;

        for (var i = 0; i < chars.Length; i++)
        {
            if (capitalizeNext && char.IsLetter(chars[i]))
            {
                chars[i] = char.ToUpper(chars[i]);
                capitalizeNext = false;
            }

            if (chars[i] == '.' || chars[i] == '!' || chars[i] == '?')
                capitalizeNext = true;
        }

        return new string(chars);
    }

    private static string FixLowercaseI(string text)
    {
        var words = text.Split(' ');
        for (var i = 0; i < words.Length; i++)
        {
            if (words[i] == "i")
                words[i] = "I";
            else if (words[i].StartsWith("i'", StringComparison.Ordinal) && words[i].Length > 2)
                words[i] = "I" + words[i][1..];
        }
        return string.Join(' ', words);
    }
}
