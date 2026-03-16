using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Verbalize.Services;

namespace Verbalize.Views;

public partial class DictionaryPage : Page
{
    private readonly AppState _appState = AppState.Instance;

    public DictionaryPage()
    {
        InitializeComponent();
        Loaded += (_, _) => RefreshList();
    }

    private void RefreshList()
    {
        var entries = _appState.Config.DictionaryEntries;

        if (FilterManual.IsChecked == true)
            entries = entries.Where(e => e.Source == "manual").ToList();
        else if (FilterAuto.IsChecked == true)
            entries = entries.Where(e => e.Source == "auto").ToList();

        WordList.ItemsSource = entries.OrderBy(e => e.Word).ToList();
    }

    private void AddWord_Click(object sender, RoutedEventArgs e) => AddWord();

    private void NewWordBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) AddWord();
    }

    private void AddWord()
    {
        var word = NewWordBox.Text.Trim();
        if (string.IsNullOrEmpty(word)) return;

        _appState.Config.AddDictionaryEntry(word, "manual");
        NewWordBox.Clear();
        RefreshList();
    }

    private void RemoveWord_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string word)
        {
            _appState.Config.RemoveDictionaryEntry(word);
            RefreshList();
        }
    }

    private void Filter_Changed(object sender, RoutedEventArgs e) => RefreshList();
}
