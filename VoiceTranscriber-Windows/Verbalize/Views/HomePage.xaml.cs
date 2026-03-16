using System.Windows;
using System.Windows.Controls;
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
            var recent = transcripts.Take(10).ToList();

            RecentList.ItemsSource = recent;
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
}
