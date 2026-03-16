namespace Verbalize.Models;

public class DictionaryEntry
{
    public string Word { get; set; } = string.Empty;
    public string Source { get; set; } = "manual"; // "manual" or "auto"
    public DateTime AddedDate { get; set; } = DateTime.UtcNow;
}
