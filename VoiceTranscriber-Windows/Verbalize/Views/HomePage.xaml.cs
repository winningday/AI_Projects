using System.Windows;
using System.Windows.Controls;
using Verbalize.Models;
using Verbalize.Services;

namespace Verbalize.Views;

public partial class HomePage : Page
{
    private readonly AppState _appState = AppState.Instance;

    public HomePage()
    {
        InitializeComponent();
        _appState.TranscriptionCompleted += RefreshData;
        Loaded += (_, _) => RefreshData();
    }

    private void RefreshData()
    {
        Dispatcher.Invoke(() =>
        {
            var transcripts = _appState.Database.LoadAll();
            var recent = transcripts.Take(50).ToList();

            var grouped = GroupByDate(recent);
            GroupedList.ItemsSource = grouped;
            TranscriptCountText.Text = transcripts.Count.ToString();

            EmptyStateText.Visibility = recent.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

            // Calculate WPM
            if (_appState.TotalRecordingTime > 5 && _appState.TotalWords > 0)
            {
                var wpm = (int)(_appState.TotalWords / (_appState.TotalRecordingTime / 60.0));
                WpmText.Text = wpm.ToString();

                var speedMultiplier = (double)wpm / _appState.Config.TypingSpeedWpm;
                SpeedText.Text = $"{speedMultiplier:F1}x";
            }

            // Translation banner
            if (_appState.Config.TranslationEnabled)
            {
                TranslationBanner.Visibility = Visibility.Visible;
                TranslationLanguageText.Text = _appState.Config.TargetLanguage;
            }
            else
            {
                TranslationBanner.Visibility = Visibility.Collapsed;
            }
        });
    }

    private static List<TranscriptGroup> GroupByDate(List<Transcript> transcripts)
    {
        var today = DateTime.Today;
        var yesterday = today.AddDays(-1);

        return transcripts
            .GroupBy(t =>
            {
                var date = t.Timestamp.ToLocalTime().Date;
                if (date == today) return "Today";
                if (date == yesterday) return "Yesterday";
                return date.ToString("MMM d, yyyy");
            })
            .Select(g => new TranscriptGroup
            {
                Key = g.Key,
                Transcripts = g.Select(t => new TranscriptDisplay(t, g.Key)).ToList()
            })
            .ToList();
    }
}

public class TranscriptGroup
{
    public string Key { get; set; } = "";
    public List<TranscriptDisplay> Transcripts { get; set; } = new();
}

public class TranscriptDisplay
{
    private readonly Transcript _transcript;
    private readonly string _groupKey;

    public TranscriptDisplay(Transcript transcript, string groupKey)
    {
        _transcript = transcript;
        _groupKey = groupKey;
    }

    public string CleanedText => _transcript.CleanedText;
    public int WordCount => _transcript.WordCount;

    public string TimeDisplay
    {
        get
        {
            var local = _transcript.Timestamp.ToLocalTime();
            if (_groupKey == "Today" || _groupKey == "Yesterday")
                return local.ToString("h:mm tt");
            return local.ToString("h:mm tt");
        }
    }
}
