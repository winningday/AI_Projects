// Module: Cohere Transcribe speech-to-text client — best accuracy (5.42% WER), free API tier
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;

namespace Verbalize.Services;

public class CohereTranscribeClient
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(30) };
    private const string BaseUrl = "https://api.cohere.com/v2/audio/transcriptions";

    public static async Task<string> TranscribeAsync(
        string audioFilePath,
        string apiKey,
        IReadOnlyList<string>? dictionaryWords = null,
        string? languageHint = null)
    {
        var audioData = await File.ReadAllBytesAsync(audioFilePath);
        if (audioData.Length == 0)
            throw new Exception("Audio file is empty.");

        using var content = new MultipartFormDataContent();

        // Model
        content.Add(new StringContent("cohere-transcribe-03-2026"), "model");

        // Language
        if (!string.IsNullOrEmpty(languageHint))
            content.Add(new StringContent(languageHint), "language");

        // Audio file — Windows records WAV natively, so no conversion needed
        var mimeType = audioFilePath.EndsWith(".wav", StringComparison.OrdinalIgnoreCase)
            ? "audio/wav" : "audio/mpeg";
        var fileContent = new ByteArrayContent(audioData);
        fileContent.Headers.ContentType = new MediaTypeHeaderValue(mimeType);
        content.Add(fileContent, "file", Path.GetFileName(audioFilePath));

        using var request = new HttpRequestMessage(HttpMethod.Post, BaseUrl);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
        request.Content = content;

        var response = await Http.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
            throw new Exception($"Cohere API error ({response.StatusCode}): {responseBody}");

        using var doc = JsonDocument.Parse(responseBody);
        var text = doc.RootElement.GetProperty("text").GetString();

        return text ?? "";
    }
}
