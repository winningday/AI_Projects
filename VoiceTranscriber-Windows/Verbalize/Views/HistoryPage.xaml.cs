using System.Windows;
using System.Windows.Controls;
using Verbalize.Models;
using Verbalize.Services;

namespace Verbalize.Views;

public partial class HistoryPage : Page
{
    private readonly AppState _appState = AppState.Instance;

    public HistoryPage()
    {
        InitializeComponent();
        _appState.TranscriptionCompleted += () => Dispatcher.Invoke(LoadTranscripts);
        Loaded += (_, _) => LoadTranscripts();
    }

    private void LoadTranscripts()
    {
        var query = SearchBox.Text.Trim();
        var transcripts = string.IsNullOrEmpty(query)
            ? _appState.Database.LoadAll()
            : _appState.Database.Search(query);

        TranscriptList.ItemsSource = transcripts;
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e) => LoadTranscripts();

    private void TranscriptList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (TranscriptList.SelectedItem is Transcript t)
        {
            NoSelectionText.Visibility = Visibility.Collapsed;
            DetailContent.Visibility = Visibility.Visible;

            CleanedTextBlock.Text = t.CleanedText;
            OriginalTextBlock.Text = t.OriginalText;
            DurationText.Text = $"{t.DurationSeconds:F1}s";
            WordCountText.Text = t.WordCount.ToString();
        }
    }

    private void CopyButton_Click(object sender, RoutedEventArgs e)
    {
        if (TranscriptList.SelectedItem is Transcript t)
        {
            Clipboard.SetText(t.CleanedText);
        }
    }

    private void DeleteButton_Click(object sender, RoutedEventArgs e)
    {
        if (TranscriptList.SelectedItem is Transcript t)
        {
            var result = MessageBox.Show("Delete this transcript?", "Confirm",
                MessageBoxButton.YesNo, MessageBoxImage.Question);
            if (result == MessageBoxResult.Yes)
            {
                _appState.Database.Delete(t.Id);
                LoadTranscripts();
                DetailContent.Visibility = Visibility.Collapsed;
                NoSelectionText.Visibility = Visibility.Visible;
            }
        }
    }
}
