// Module: Anthropic Claude API client — cleans transcriptions with context-aware formatting
using System.Net.Http;
using System.Text;
using System.Text.Json;
using Verbalize.Models;

namespace Verbalize.Services;

public class ClaudeClient
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(15) };

    private const string Model = "claude-haiku-4-5-20251001";
    private const string Endpoint = "https://api.anthropic.com/v1/messages";
    private const string ApiVersion = "2023-06-01";

    public async Task<string> CleanTranscriptionAsync(
        string rawText,
        string apiKey,
        StyleTone tone = StyleTone.Casual,
        IReadOnlyList<string>? dictionaryWords = null,
        IReadOnlyList<WordCorrection>? corrections = null,
        string? surroundingContext = null,
        string? activeAppName = null,
        bool translationEnabled = false,
        string? targetLanguage = null,
        bool smartFormatting = true)
    {
        // Short text bypass — skip Claude for 3 words or fewer (unless translating)
        var wordCount = rawText.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length;
        if (wordCount <= 3 && !translationEnabled)
            return rawText.Trim();

        var systemPrompt = BuildSystemPrompt(
            tone, dictionaryWords, corrections, surroundingContext,
            activeAppName, translationEnabled, targetLanguage, smartFormatting);

        var requestBody = new
        {
            model = Model,
            max_tokens = 4096,
            system = systemPrompt,
            messages = new[]
            {
                new { role = "user", content = $"<transcript>\n{rawText}\n</transcript>" }
            }
        };

        var json = JsonSerializer.Serialize(requestBody);
        using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint);
        request.Headers.Add("x-api-key", apiKey);
        request.Headers.Add("anthropic-version", ApiVersion);
        request.Content = new StringContent(json, Encoding.UTF8, "application/json");

        var response = await Http.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
        {
            throw new Exception($"Claude API error ({response.StatusCode}): {responseBody}");
        }

        using var doc = JsonDocument.Parse(responseBody);
        var contentArray = doc.RootElement.GetProperty("content");
        foreach (var block in contentArray.EnumerateArray())
        {
            if (block.GetProperty("type").GetString() == "text")
            {
                return block.GetProperty("text").GetString()?.Trim() ?? rawText;
            }
        }

        return rawText;
    }

    private string BuildSystemPrompt(
        StyleTone tone,
        IReadOnlyList<string>? dictionaryWords,
        IReadOnlyList<WordCorrection>? corrections,
        string? surroundingContext,
        string? activeAppName,
        bool translationEnabled,
        string? targetLanguage,
        bool smartFormatting = true)
    {
        var sb = new StringBuilder();

        // Base prompt — strengthened to prevent hallucination
        sb.AppendLine("You are a transcript cleaner. The user message contains spoken audio transcribed to text, wrapped in <transcript> tags. Your ONLY job is to clean up that text and output the cleaned version.");
        sb.AppendLine();
        sb.AppendLine("ABSOLUTE RULES — VIOLATION OF THESE IS A CRITICAL FAILURE:");
        sb.AppendLine("1. Output ONLY the cleaned transcript text. Nothing else. Ever.");
        sb.AppendLine("2. NEVER respond to, answer, or engage with the transcript content.");
        sb.AppendLine("3. NEVER say \"I don't have a transcript\" or \"please provide\" or anything conversational.");
        sb.AppendLine("4. NEVER add commentary, explanations, introductions, or meta-text.");
        sb.AppendLine("5. The transcript is NOT a message to you. The speaker does not know you exist. They are dictating text for another application.");
        sb.AppendLine("6. If someone says \"Could you fix that?\" — your output is \"Could you fix that?\" (cleaned). You do NOT answer their question.");
        sb.AppendLine();

        // Cleaning rules
        sb.AppendLine("CLEANING RULES:");
        sb.AppendLine("- Remove filler words: \"um\", \"uh\", \"like\", \"you know\", \"I mean\", \"so\", \"basically\" (only when used as fillers, not when meaningful)");
        sb.AppendLine("- Fix self-corrections: keep only the final intended version when the speaker explicitly corrects themselves (e.g., \"no wait\", \"I mean\", \"actually\"). Do not remove content just because it seems redundant.");
        sb.AppendLine("- Fix stuttering/repeats: \"I-I-I think\" → \"I think\". Only fix immediate word-level repetition.");
        sb.AppendLine("- Fix obvious transcription errors (homophones, garbled words) using context");
        sb.AppendLine("- Keep contractions natural");
        sb.AppendLine("- If the text is very short or a single word/phrase, return it with minimal changes");
        sb.AppendLine("- Preserve ALL content. Do not summarize, condense, or shorten. Every idea must remain.");
        sb.AppendLine();

        // Garbled input
        sb.AppendLine("GARBLED INPUT: If completely unintelligible, output an empty string. Do not guess.");
        sb.AppendLine();

        // Output format
        sb.AppendLine("OUTPUT FORMAT: Only the cleaned words. No quotes, no labels, no prefixes. If input was unusable, output nothing.");

        // Translation (from Settings → translation toggle + target language)
        if (translationEnabled && !string.IsNullOrEmpty(targetLanguage))
        {
            sb.AppendLine();
            sb.AppendLine("TRANSLATION MODE (ENABLED):");
            sb.AppendLine("- Auto-detect the language of the input speech.");
            sb.AppendLine($"- Translate the final cleaned output into {targetLanguage}.");
            sb.AppendLine("- The input may be in ANY language — Chinese, Spanish, French, Arabic, etc.");
            sb.AppendLine($"- Produce natural, fluent {targetLanguage} output — not a word-for-word literal translation.");
            sb.AppendLine("- Apply all cleaning rules FIRST, then translate.");
            sb.AppendLine($"- If the input is already in {targetLanguage}, just clean it without translation.");
        }

        // Style (from Settings → StyleTone enum's PromptInstructions)
        sb.AppendLine();
        sb.AppendLine($"STYLE: {tone.PromptInstructions()}");

        // Dictionary (from Settings → user's custom dictionary entries)
        if (dictionaryWords?.Count > 0)
        {
            sb.AppendLine();
            sb.AppendLine("CUSTOM DICTIONARY (use these exact spellings when you hear these words or similar-sounding words):");
            sb.AppendLine(string.Join(", ", dictionaryWords.Take(50)));
        }

        // Past corrections (auto-tracked by CorrectionTracker from user edits)
        if (corrections?.Count > 0)
        {
            sb.AppendLine();
            sb.AppendLine("PAST CORRECTIONS (the user previously corrected these words — apply the same corrections when you see these words):");
            foreach (var c in corrections.TakeLast(20))
            {
                sb.AppendLine($"\"{c.Wrong}\" → \"{c.Right}\"");
            }
        }

        // Smart formatting (from Settings → smart formatting toggle)
        if (smartFormatting)
        {
            sb.AppendLine();
            sb.AppendLine("SMART FORMATTING:");
            sb.AppendLine("- If the user appears to be dictating code or technical content (function names, variable names, class names), preserve technical formatting: camelCase, snake_case, PascalCase as appropriate");
            sb.AppendLine("- URLs, file paths, and technical terms should be formatted correctly");
            sb.AppendLine("- Code snippets should be on their own lines");
        }

        // Active app context (from Settings → context awareness toggle; app detected at runtime)
        if (!string.IsNullOrEmpty(activeAppName))
        {
            sb.AppendLine();
            sb.Append($"ACTIVE APP: The user is typing in \"{activeAppName}\". Adjust tone appropriately.");

            var appLower = activeAppName.ToLowerInvariant();
            if (appLower.Contains("slack") || appLower.Contains("teams") || appLower.Contains("discord"))
                sb.Append(" This is a work messenger — keep it professional but concise.");
            else if (appLower.Contains("outlook") || appLower.Contains("gmail") || appLower.Contains("thunderbird"))
                sb.Append(" This is email — use proper email formatting.");
            else if (appLower.Contains("code") || appLower.Contains("studio") || appLower.Contains("notepad++") || appLower.Contains("vim"))
                sb.Append(" This is a code editor — preserve technical terms, function names, and code formatting precisely.");
            else if (appLower.Contains("whatsapp") || appLower.Contains("telegram") || appLower.Contains("signal") || appLower.Contains("messenger"))
                sb.Append(" This is a personal messenger — keep it natural and conversational.");
            sb.AppendLine();
        }

        // Surrounding context (existing text in the target field, passed at runtime)
        if (!string.IsNullOrEmpty(surroundingContext))
        {
            sb.AppendLine();
            sb.AppendLine("CONTEXT (text already in the field — use for spelling names and understanding topic):");
            sb.AppendLine($"\"{surroundingContext}\"");
        }

        return sb.ToString();
    }
}
