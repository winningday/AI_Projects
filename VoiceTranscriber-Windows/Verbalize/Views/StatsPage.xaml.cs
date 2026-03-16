using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using Verbalize.Services;

namespace Verbalize.Views;

public partial class StatsPage : Page
{
    private readonly AppState _appState = AppState.Instance;

    public StatsPage()
    {
        InitializeComponent();
        Loaded += (_, _) => RefreshStats();
        _appState.TranscriptionCompleted += () => Dispatcher.Invoke(RefreshStats);
    }

    private void RefreshStats()
    {
        var transcripts = _appState.Database.LoadAll();
        var totalWords = _appState.TotalWords;
        var totalTime = _appState.TotalRecordingTime;
        var typingWpm = _appState.Config.TypingSpeedWpm;

        TotalWordsText.Text = totalWords.ToString("N0");
        TotalTranscriptsText.Text = transcripts.Count.ToString();
        RecordingTimeText.Text = totalTime > 60
            ? $"{totalTime / 60:F0}m"
            : $"{totalTime:F0}s";

        // Speed comparison
        if (totalTime > 5 && totalWords > 0)
        {
            var voiceWpm = totalWords / (totalTime / 60.0);
            var multiplier = voiceWpm / typingWpm;
            SpeedMultiplierText.Text = $"{multiplier:F1}x faster";
            SpeedDetailText.Text = $"Voice: {voiceWpm:F0} WPM  |  Typing: {typingWpm} WPM";
        }

        // Average words per transcript
        if (transcripts.Count > 0)
        {
            var avg = totalWords / transcripts.Count;
            AvgWordsText.Text = avg.ToString();
        }

        // Time saved
        if (totalWords > 0 && typingWpm > 0)
        {
            var typingMinutes = (double)totalWords / typingWpm;
            var voiceMinutes = totalTime / 60.0;
            var saved = typingMinutes - voiceMinutes;
            TimeSavedText.Text = saved > 0 ? $"{saved:F0} min" : "0 min";
        }

        // Weekly chart
        RenderWeeklyChart(transcripts);
    }

    private void RenderWeeklyChart(List<Models.Transcript> allTranscripts)
    {
        WeeklyChart.Children.Clear();
        WeeklyChart.ColumnDefinitions.Clear();

        var today = DateTime.UtcNow.Date;
        var dayData = new int[7];

        for (int i = 0; i < 7; i++)
        {
            var day = today.AddDays(-6 + i);
            dayData[i] = allTranscripts
                .Where(t => t.Timestamp.Date == day)
                .Sum(t => t.WordCount);
        }

        var maxVal = dayData.Max();
        if (maxVal == 0) maxVal = 1;

        for (int i = 0; i < 7; i++)
        {
            WeeklyChart.ColumnDefinitions.Add(new ColumnDefinition());

            var stack = new StackPanel
            {
                VerticalAlignment = VerticalAlignment.Bottom,
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(4, 0, 4, 0)
            };

            // Bar
            var barHeight = (dayData[i] / (double)maxVal) * 80;
            var bar = new Rectangle
            {
                Width = 24,
                Height = Math.Max(barHeight, 4),
                RadiusX = 4,
                RadiusY = 4,
                Fill = (SolidColorBrush)FindResource("PrimaryBrush")
            };
            stack.Children.Add(bar);

            // Day label
            var day = today.AddDays(-6 + i);
            var label = new TextBlock
            {
                Text = day.ToString("ddd"),
                FontSize = 11,
                Foreground = (SolidColorBrush)FindResource("TextMutedBrush"),
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(0, 4, 0, 0)
            };
            stack.Children.Add(label);

            Grid.SetColumn(stack, i);
            WeeklyChart.Children.Add(stack);
        }
    }
}
