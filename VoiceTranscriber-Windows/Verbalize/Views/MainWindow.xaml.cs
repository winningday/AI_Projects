using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using Verbalize.Services;

namespace Verbalize.Views;

public partial class MainWindow : Window
{
    private readonly AppState _appState = AppState.Instance;
    private RecordingOverlay? _recordingOverlay;

    // Pages cached for navigation
    private readonly HomePage _homePage = new();
    private readonly HistoryPage _historyPage = new();
    private readonly StatsPage _statsPage = new();
    private readonly DictionaryPage _dictionaryPage = new();
    private readonly StylePage _stylePage = new();
    private readonly SettingsPage _settingsPage = new();

    public string HotkeyDescription => _appState.HotKeyManager.HotkeyDescription;

    public MainWindow()
    {
        InitializeComponent();
        DataContext = _appState;

        // Wire up recording overlay
        _appState.RecordingStarted += OnRecordingStarted;
        _appState.RecordingStopped += OnRecordingStopped;

        // Show onboarding if first run
        if (!_appState.Config.HasCompletedOnboarding)
        {
            Loaded += (_, _) =>
            {
                var onboarding = new OnboardingWindow();
                onboarding.Owner = this;
                onboarding.ShowDialog();
            };
        }

        ContentFrame.Content = _homePage;
    }

    private void NavList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (NavList.SelectedIndex < 0) return;

        ContentFrame.Content = NavList.SelectedIndex switch
        {
            0 => _homePage,
            1 => _historyPage,
            2 => _statsPage,
            3 => _dictionaryPage,
            4 => _stylePage,
            5 => _settingsPage,
            _ => _homePage
        };
    }

    private void OnRecordingStarted()
    {
        Dispatcher.Invoke(() =>
        {
            _recordingOverlay ??= new RecordingOverlay();
            _recordingOverlay.Show();
        });
    }

    private void OnRecordingStopped()
    {
        Dispatcher.Invoke(() =>
        {
            _recordingOverlay?.Hide();
        });
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        if (_appState.Config.MinimizeToTray)
        {
            e.Cancel = true;
            Hide();
        }
        else
        {
            _recordingOverlay?.Close();
            Application.Current.Shutdown();
        }
    }
}
