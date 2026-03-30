// Module: OpenAI Whisper API client — transcribes audio files with dictionary hints
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;

namespace Verbalize.Services;

public class WhisperClient
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(30) };

    private const string PrimaryModel = "gpt-4o-mini-transcribe";
    private const string FallbackModel = "whisper-1";
    private const string Endpoint = "https://api.openai.com/v1/audio/transcriptions";

    public async Task<string> TranscribeAsync(
        string audioFilePath,
        string apiKey,
        IReadOnlyList<string>? dictionaryWords = null,
        string? languageHint = null,
        string? contextHint = null,
        string? model = null)
    {
        var selectedModel = model ?? PrimaryModel;
        // Try selected model first, fall back to whisper-1
        try
        {
            return await TranscribeWithModelAsync(
                audioFilePath, apiKey, selectedModel, dictionaryWords, languageHint, contextHint);
        }
        catch
        {
            return await TranscribeWithModelAsync(
                audioFilePath, apiKey, FallbackModel, dictionaryWords, languageHint, contextHint);
        }
    }

    private async Task<string> TranscribeWithModelAsync(
        string audioFilePath,
        string apiKey,
        string model,
        IReadOnlyList<string>? dictionaryWords,
        string? languageHint,
        string? contextHint)
    {
        using var content = new MultipartFormDataContent();

        // Audio file
        var audioBytes = await File.ReadAllBytesAsync(audioFilePath);
        var audioContent = new ByteArrayContent(audioBytes);
        audioContent.Headers.ContentType = new MediaTypeHeaderValue("audio/wav");
        content.Add(audioContent, "file", Path.GetFileName(audioFilePath));

        // Model
        content.Add(new StringContent(model), "model");

        // Response format
        content.Add(new StringContent("json"), "response_format");

        // Language hint (skip if translation is enabled — let Whisper auto-detect)
        if (!string.IsNullOrEmpty(languageHint))
        {
            content.Add(new StringContent(languageHint), "language");
        }

        // Build prompt with dictionary words and context
        var promptParts = new List<string>();

        if (dictionaryWords?.Count > 0)
        {
            var words = dictionaryWords.Take(50);
            promptParts.Add(string.Join(", ", words));
        }

        if (!string.IsNullOrEmpty(contextHint))
        {
            promptParts.Add($"Context: {contextHint}");
        }

        if (promptParts.Count > 0)
        {
            content.Add(new StringContent(string.Join(". ", promptParts)), "prompt");
        }

        using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
        request.Content = content;

        var response = await Http.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
        {
            throw new Exception($"Whisper API error ({response.StatusCode}): {responseBody}");
        }

        using var doc = JsonDocument.Parse(responseBody);
        return doc.RootElement.GetProperty("text").GetString() ?? string.Empty;
    }
}
