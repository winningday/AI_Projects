namespace Verbalize.Models;

public class Transcript
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    public string OriginalText { get; set; } = string.Empty;
    public string CleanedText { get; set; } = string.Empty;
    public double DurationSeconds { get; set; }
    public string? CorrectedText { get; set; }

    public int WordCount => string.IsNullOrWhiteSpace(CleanedText)
        ? 0
        : CleanedText.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length;
}
