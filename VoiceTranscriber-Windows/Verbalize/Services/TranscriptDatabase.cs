// Module: SQLite database for transcript storage and retrieval
using Microsoft.Data.Sqlite;
using Verbalize.Models;

namespace Verbalize.Services;

public class TranscriptDatabase : IDisposable
{
    private readonly string _connectionString;

    public TranscriptDatabase()
    {
        var dbDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Verbalize");
        Directory.CreateDirectory(dbDir);

        var dbPath = Path.Combine(dbDir, "transcripts.sqlite");
        _connectionString = $"Data Source={dbPath}";

        InitializeDatabase();
    }

    private void InitializeDatabase()
    {
        using var conn = new SqliteConnection(_connectionString);
        conn.Open();

        using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
            CREATE TABLE IF NOT EXISTS transcripts (
                id TEXT PRIMARY KEY,
                timestamp TEXT NOT NULL,
                originalText TEXT NOT NULL,
                cleanedText TEXT NOT NULL,
                durationSeconds REAL NOT NULL,
                correctedText TEXT
            )";
        cmd.ExecuteNonQuery();
    }

    public void Save(Transcript transcript)
    {
        using var conn = new SqliteConnection(_connectionString);
        conn.Open();

        using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
            INSERT OR REPLACE INTO transcripts (id, timestamp, originalText, cleanedText, durationSeconds, correctedText)
            VALUES (@id, @timestamp, @original, @cleaned, @duration, @corrected)";

        cmd.Parameters.AddWithValue("@id", transcript.Id);
        cmd.Parameters.AddWithValue("@timestamp", transcript.Timestamp.ToString("O"));
        cmd.Parameters.AddWithValue("@original", transcript.OriginalText);
        cmd.Parameters.AddWithValue("@cleaned", transcript.CleanedText);
        cmd.Parameters.AddWithValue("@duration", transcript.DurationSeconds);
        cmd.Parameters.AddWithValue("@corrected", (object?)transcript.CorrectedText ?? DBNull.Value);

        cmd.ExecuteNonQuery();
    }

    public List<Transcript> LoadAll()
    {
        var transcripts = new List<Transcript>();

        using var conn = new SqliteConnection(_connectionString);
        conn.Open();

        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM transcripts ORDER BY timestamp DESC";

        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            transcripts.Add(new Transcript
            {
                Id = reader.GetString(0),
                Timestamp = DateTime.Parse(reader.GetString(1)),
                OriginalText = reader.GetString(2),
                CleanedText = reader.GetString(3),
                DurationSeconds = reader.GetDouble(4),
                CorrectedText = reader.IsDBNull(5) ? null : reader.GetString(5)
            });
        }

        return transcripts;
    }

    public List<Transcript> Search(string query)
    {
        var transcripts = new List<Transcript>();

        using var conn = new SqliteConnection(_connectionString);
        conn.Open();

        using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
            SELECT * FROM transcripts
            WHERE originalText LIKE @query OR cleanedText LIKE @query
            ORDER BY timestamp DESC";
        cmd.Parameters.AddWithValue("@query", $"%{query}%");

        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            transcripts.Add(new Transcript
            {
                Id = reader.GetString(0),
                Timestamp = DateTime.Parse(reader.GetString(1)),
                OriginalText = reader.GetString(2),
                CleanedText = reader.GetString(3),
                DurationSeconds = reader.GetDouble(4),
                CorrectedText = reader.IsDBNull(5) ? null : reader.GetString(5)
            });
        }

        return transcripts;
    }

    public void Delete(string id)
    {
        using var conn = new SqliteConnection(_connectionString);
        conn.Open();

        using var cmd = conn.CreateCommand();
        cmd.CommandText = "DELETE FROM transcripts WHERE id = @id";
        cmd.Parameters.AddWithValue("@id", id);
        cmd.ExecuteNonQuery();
    }

    public void DeleteAll()
    {
        using var conn = new SqliteConnection(_connectionString);
        conn.Open();

        using var cmd = conn.CreateCommand();
        cmd.CommandText = "DELETE FROM transcripts";
        cmd.ExecuteNonQuery();
    }

    public List<Transcript> GetTranscriptsForDateRange(DateTime start, DateTime end)
    {
        var transcripts = new List<Transcript>();

        using var conn = new SqliteConnection(_connectionString);
        conn.Open();

        using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
            SELECT * FROM transcripts
            WHERE timestamp >= @start AND timestamp <= @end
            ORDER BY timestamp DESC";
        cmd.Parameters.AddWithValue("@start", start.ToString("O"));
        cmd.Parameters.AddWithValue("@end", end.ToString("O"));

        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            transcripts.Add(new Transcript
            {
                Id = reader.GetString(0),
                Timestamp = DateTime.Parse(reader.GetString(1)),
                OriginalText = reader.GetString(2),
                CleanedText = reader.GetString(3),
                DurationSeconds = reader.GetDouble(4),
                CorrectedText = reader.IsDBNull(5) ? null : reader.GetString(5)
            });
        }

        return transcripts;
    }

    public void Dispose() { }
}
