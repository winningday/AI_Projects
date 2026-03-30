// Module: Claude direct audio transcription — transcribes + cleans in a single API call
using System.Net.Http;
using System.Text;
using System.Text.Json;
using Verbalize.Models;

namespace Verbalize.Services;

public class ClaudeAudioClient
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(30) };
    private const string Endpoint = "https://api.anthropic.com/v1/messages";
    private const string ApiVersion = "2023-06-01";
    private const string Model = "claude-sonnet-4-5-20250514";

    public async Task<(string RawText, string CleanedText)> TranscribeAndCleanAsync(
        string audioFilePath,
        string apiKey,
        StyleTone tone = StyleTone.Casual,
        IReadOnlyList<string>? dictionaryWords = null,
        IReadOnlyList<WordCorrection>? corrections = null,
        string? activeAppName = null,
        bool translationEnabled = false,
        string? targetLanguage = null,
        bool smartFormatting = true)
    {
        var audioData = await File.ReadAllBytesAsync(audioFilePath);
        if (audioData.Length == 0)
            throw new Exception("Audio file is empty.");

        var base64Audio = Convert.ToBase64String(audioData);
        var mediaType = audioFilePath.EndsWith(".wav", StringComparison.OrdinalIgnoreCase)
            ? "audio/wav" : "audio/mp4";

        var systemPrompt = BuildSystemPrompt(tone, dictionaryWords, corrections,
            activeAppName, translationEnabled, targetLanguage, smartFormatting);

        // Build request with audio content block
        var requestObj = new
        {
            model = Model,
            max_tokens = 4096,
            system = systemPrompt,
            messages = new object[]
            {
                new
                {
                    role = "user",
                    content = new object[]
                    {
                        new
                        {
                            type = "audio",
                            source = new
                            {
                                type = "base64",
                                media_type = mediaType,
                                data = base64Audio
                            }
                        },
                        new
                        {
                            type = "text",
                            text = "Transcribe this audio and apply the cleaning rules. Output ONLY the cleaned transcription."
                        }
                    }
                }
            }
        };

        var json = JsonSerializer.Serialize(requestObj);
        using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint);
        request.Headers.Add("x-api-key", apiKey);
        request.Headers.Add("anthropic-version", ApiVersion);
        request.Content = new StringContent(json, Encoding.UTF8, "application/json");

        var response = await Http.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
            throw new Exception($"Claude Audio API error ({response.StatusCode}): {responseBody}");

        using var doc = JsonDocument.Parse(responseBody);
        var contentArray = doc.RootElement.GetProperty("content");
        foreach (var block in contentArray.EnumerateArray())
        {
            if (block.GetProperty("type").GetString() == "text")
            {
                var text = block.GetProperty("text").GetString()?.Trim() ?? "";
                return (text, text);
            }
        }

        throw new Exception("Claude response did not contain text.");
    }

    private string BuildSystemPrompt(
        StyleTone tone,
        IReadOnlyList<string>? dictionaryWords,
        IReadOnlyList<WordCorrection>? corrections,
        string? activeAppName,
        bool translationEnabled,
        string? targetLanguage,
        bool smartFormatting)
    {
        var sb = new StringBuilder();

        sb.AppendLine("You are a voice transcription assistant. You will receive an audio recording of someone speaking.");
        sb.AppendLine("Your job is to transcribe the speech accurately and clean it up. Output ONLY the final cleaned text.");
        sb.AppendLine();
        sb.AppendLine("TRANSCRIPTION RULES:");
        sb.AppendLine("- Transcribe the speech exactly as spoken — capture every word accurately");
        sb.AppendLine("- Use proper spelling for all words, names, and technical terms");
        sb.AppendLine("- Do NOT add words the speaker didn't say");
        sb.AppendLine("- Do NOT interpret or respond to the content — just transcribe and clean it");
        sb.AppendLine();
        sb.AppendLine("CLEANING RULES:");
        sb.AppendLine("- Remove filler words: \"um\", \"uh\", \"like\", \"you know\", \"I mean\", \"so\", \"basically\" (only when used as fillers)");
        sb.AppendLine("- Fix self-corrections: keep only the final intended version when speaker corrects themselves");
        sb.AppendLine("- Fix stuttering/repeats: \"I-I-I think\" → \"I think\"");
        sb.AppendLine("- Preserve ALL content — every idea the speaker expressed must remain");
        sb.AppendLine("- If audio is unintelligible, output an empty string");
        sb.AppendLine();
        sb.AppendLine("OUTPUT FORMAT: Only the cleaned transcription. No quotes, labels, or commentary.");

        if (translationEnabled && !string.IsNullOrEmpty(targetLanguage))
        {
            sb.AppendLine();
            sb.AppendLine($"TRANSLATION: Translate the final output into {targetLanguage}. Apply cleaning first, then translate.");
        }

        sb.AppendLine();
        sb.AppendLine($"STYLE: {tone.PromptInstructions()}");

        if (dictionaryWords?.Count > 0)
        {
            sb.AppendLine();
            sb.AppendLine($"CUSTOM DICTIONARY (use these exact spellings): {string.Join(", ", dictionaryWords.Take(50))}");
        }

        if (corrections?.Count > 0)
        {
            var lines = corrections.TakeLast(20).Select(c => $"\"{c.Wrong}\" → \"{c.Right}\"");
            sb.AppendLine();
            sb.AppendLine($"PAST CORRECTIONS (apply same fixes): {string.Join(", ", lines)}");
        }

        if (smartFormatting)
        {
            sb.AppendLine();
            sb.AppendLine("SMART FORMATTING: Preserve camelCase, snake_case, PascalCase. Format URLs and file paths correctly.");
        }

        if (!string.IsNullOrEmpty(activeAppName))
        {
            sb.AppendLine();
            sb.AppendLine($"ACTIVE APP: \"{activeAppName}\". Adjust tone appropriately.");
        }

        return sb.ToString();
    }
}
