// Module: Deepgram Nova-2 speech-to-text client — fast, accurate cloud transcription
using System.Net.Http;
using System.Text.Json;

namespace Verbalize.Services;

public class DeepgramClient
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(30) };
    private const string BaseUrl = "https://api.deepgram.com/v1/listen";

    public async Task<string> TranscribeAsync(
        string audioFilePath,
        string apiKey,
        IReadOnlyList<string>? dictionaryWords = null,
        string? languageHint = null)
    {
        var audioData = await File.ReadAllBytesAsync(audioFilePath);
        if (audioData.Length == 0)
            throw new Exception("Audio file is empty.");

        // Build query parameters
        var queryParams = new List<string>
        {
            "model=nova-2",
            "smart_format=true",
            "punctuate=true",
            "filler_words=false"
        };

        if (!string.IsNullOrEmpty(languageHint))
            queryParams.Add($"language={languageHint}");

        if (dictionaryWords?.Count > 0)
        {
            var keywords = string.Join(",", dictionaryWords.Take(50));
            queryParams.Add($"keywords={Uri.EscapeDataString(keywords)}");
        }

        var url = $"{BaseUrl}?{string.Join("&", queryParams)}";
        var mimeType = audioFilePath.EndsWith(".wav", StringComparison.OrdinalIgnoreCase)
            ? "audio/wav" : "audio/mp4";

        using var request = new HttpRequestMessage(HttpMethod.Post, url);
        request.Headers.Add("Authorization", $"Token {apiKey}");
        request.Content = new ByteArrayContent(audioData);
        request.Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue(mimeType);

        var response = await Http.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
            throw new Exception($"Deepgram API error ({response.StatusCode}): {responseBody}");

        using var doc = JsonDocument.Parse(responseBody);
        var transcript = doc.RootElement
            .GetProperty("results")
            .GetProperty("channels")[0]
            .GetProperty("alternatives")[0]
            .GetProperty("transcript")
            .GetString();

        return transcript ?? "";
    }
}
