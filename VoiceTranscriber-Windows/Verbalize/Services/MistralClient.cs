// Module: Mistral Voxtral speech-to-text client — fast, accurate, $0.003/min
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;

namespace Verbalize.Services;

public class MistralClient
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(30) };
    private const string BaseUrl = "https://api.mistral.ai/v1/audio/transcriptions";

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
        content.Add(new StringContent("voxtral-mini-latest"), "model");

        // Language
        if (!string.IsNullOrEmpty(languageHint))
            content.Add(new StringContent(languageHint), "language");

        // Context bias (custom vocabulary)
        if (dictionaryWords?.Count > 0)
        {
            var biasString = string.Join(",", dictionaryWords.Take(100));
            content.Add(new StringContent(biasString), "context_bias");
        }

        // Audio file
        var mimeType = audioFilePath.EndsWith(".wav", StringComparison.OrdinalIgnoreCase)
            ? "audio/wav" : "audio/mp4";
        var fileContent = new ByteArrayContent(audioData);
        fileContent.Headers.ContentType = new MediaTypeHeaderValue(mimeType);
        content.Add(fileContent, "file", Path.GetFileName(audioFilePath));

        using var request = new HttpRequestMessage(HttpMethod.Post, BaseUrl);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
        request.Content = content;

        var response = await Http.SendAsync(request);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
            throw new Exception($"Mistral API error ({response.StatusCode}): {responseBody}");

        using var doc = JsonDocument.Parse(responseBody);
        var text = doc.RootElement.GetProperty("text").GetString();

        return text ?? "";
    }
}
