namespace Verbalize.Models;

public class WordCorrection
{
    public string Wrong { get; set; } = string.Empty;
    public string Right { get; set; } = string.Empty;
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
}
