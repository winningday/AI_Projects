// Module: Pipeline timing logger — writes CSV + console output for performance analysis
using System.Globalization;

namespace Verbalize.Services;

public static class PipelineLogger
{
    private static readonly string LogDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Verbalize");
    private static readonly string LogFile = Path.Combine(LogDir, "pipeline_timing.csv");
    private static readonly object FileLock = new();

    private const string Header = "timestamp,engine,stt_model,transcribe_ms,cleanup_ms,cleanup_method,cleanup_model,audio_duration_s,word_count,total_ms,error";

    static PipelineLogger()
    {
        Directory.CreateDirectory(LogDir);
        if (!File.Exists(LogFile))
            File.WriteAllText(LogFile, Header + Environment.NewLine);
    }

    public static void Log(
        string engine,
        string sttModel,
        int transcribeMs,
        int cleanupMs,
        string cleanupMethod,
        string cleanupModel,
        double audioDuration,
        int wordCount,
        int? totalMs = null,
        string? error = null)
    {
        var total = totalMs ?? (transcribeMs + cleanupMs);
        var escapedError = (error ?? "").Replace(",", ";");
        var timestamp = DateTime.UtcNow.ToString("o");

        // Console/Debug output
        if (!string.IsNullOrEmpty(error))
            System.Diagnostics.Debug.WriteLine($"[Pipeline] [{engine}/{sttModel}] FAILED after {total}ms — {error}");
        else
            System.Diagnostics.Debug.WriteLine($"[Pipeline] [{engine}/{sttModel}] transcribe={transcribeMs}ms cleanup={cleanupMs}ms ({cleanupMethod}/{cleanupModel}) total={total}ms | {audioDuration:F1}s audio → {wordCount} words");

        // CSV append
        var line = $"{timestamp},{engine},{sttModel},{transcribeMs},{cleanupMs},{cleanupMethod},{cleanupModel},{audioDuration.ToString("F1", CultureInfo.InvariantCulture)},{wordCount},{total},{escapedError}";
        lock (FileLock)
        {
            try
            {
                File.AppendAllText(LogFile, line + Environment.NewLine);
            }
            catch
            {
                // Don't crash the app if logging fails
            }
        }
    }

    public static string LogFilePath => LogFile;

    public static List<PipelineEntry> RecentEntries(int count = 20)
    {
        if (!File.Exists(LogFile)) return new();

        try
        {
            var lines = File.ReadAllLines(LogFile)
                .Where(l => !string.IsNullOrWhiteSpace(l) && !l.StartsWith("timestamp"))
                .ToList();
            return lines.TakeLast(count).Reverse().Select(PipelineEntry.Parse).Where(e => e != null).Cast<PipelineEntry>().ToList();
        }
        catch
        {
            return new();
        }
    }
}

public class PipelineEntry
{
    public string Timestamp { get; init; } = "";
    public string Engine { get; init; } = "";
    public string SttModel { get; init; } = "";
    public int TranscribeMs { get; init; }
    public int CleanupMs { get; init; }
    public string CleanupMethod { get; init; } = "";
    public string CleanupModel { get; init; } = "";
    public double AudioDuration { get; init; }
    public int WordCount { get; init; }
    public int TotalMs { get; init; }
    public string? Error { get; init; }

    public string Summary =>
        !string.IsNullOrEmpty(Error)
            ? $"[{Engine}] FAILED — {Error}"
            : $"[{Engine}/{SttModel}] {TranscribeMs}ms + {CleanupMs}ms ({CleanupMethod}/{CleanupModel}) = {TotalMs}ms total | {WordCount} words";

    public static PipelineEntry? Parse(string csvLine)
    {
        var parts = csvLine.Split(',');
        if (parts.Length < 10) return null;

        string timestamp;
        if (DateTimeOffset.TryParse(parts[0], out var dto))
            timestamp = dto.LocalDateTime.ToString("h:mm:ss tt");
        else
            timestamp = parts[0];

        return new PipelineEntry
        {
            Timestamp = timestamp,
            Engine = parts[1],
            SttModel = parts[2],
            TranscribeMs = int.TryParse(parts[3], out var t) ? t : 0,
            CleanupMs = int.TryParse(parts[4], out var c) ? c : 0,
            CleanupMethod = parts[5],
            CleanupModel = parts[6],
            AudioDuration = double.TryParse(parts[7], NumberStyles.Float, CultureInfo.InvariantCulture, out var d) ? d : 0,
            WordCount = int.TryParse(parts[8], out var w) ? w : 0,
            TotalMs = int.TryParse(parts[9], out var m) ? m : 0,
            Error = parts.Length > 10 && !string.IsNullOrWhiteSpace(parts[10]) ? parts[10] : null
        };
    }
}
