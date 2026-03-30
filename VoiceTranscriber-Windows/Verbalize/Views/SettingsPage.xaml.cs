using System.Windows;
using System.Windows.Controls;
using Verbalize.Services;

namespace Verbalize.Views;

public partial class SettingsPage : Page
{
    private readonly AppState _appState = AppState.Instance;
    private bool _loading = true;

    public SettingsPage()
    {
        InitializeComponent();

        LanguageCombo.ItemsSource = AppState.SupportedLanguages;

        Loaded += (_, _) => LoadSettings();
    }

    private void LoadSettings()
    {
        _loading = true;

        HotkeyText.Text = _appState.HotKeyManager.HotkeyDescription;

        SoundEffectsCheck.IsChecked = _appState.Config.SoundEffects;
        AutoInjectCheck.IsChecked = _appState.Config.AutoInject;
        MinimizeToTrayCheck.IsChecked = _appState.Config.MinimizeToTray;
        LaunchAtStartupCheck.IsChecked = _appState.Config.LaunchAtStartup;
        UseAICleanupCheck.IsChecked = _appState.Config.UseAICleanup;
        UpdateCleanupDescription();
        ContextAwarenessCheck.IsChecked = _appState.Config.ContextAwareness;
        SmartFormattingCheck.IsChecked = _appState.Config.SmartFormatting;
        AutoDictionaryCheck.IsChecked = _appState.Config.AutoAddToDictionary;

        TranslationCheck.IsChecked = _appState.Config.TranslationEnabled;
        LanguagePanel.Visibility = _appState.Config.TranslationEnabled
            ? Visibility.Visible : Visibility.Collapsed;

        var langIdx = Array.IndexOf(AppState.SupportedLanguages, _appState.Config.TargetLanguage);
        LanguageCombo.SelectedIndex = langIdx >= 0 ? langIdx : 0;

        TypingSpeedBox.Text = _appState.Config.TypingSpeedWpm.ToString();

        // Show masked API keys
        if (!string.IsNullOrEmpty(_appState.Config.OpenAIApiKey))
            OpenAIKeyBox.Password = _appState.Config.OpenAIApiKey;
        if (!string.IsNullOrEmpty(_appState.Config.AnthropicApiKey))
            AnthropicKeyBox.Password = _appState.Config.AnthropicApiKey;

        _loading = false;
    }

    private void ChangeHotkey_Click(object sender, RoutedEventArgs e)
    {
        HotkeyHint.Text = "Press any key combination...";
        HotkeyHint.Visibility = Visibility.Visible;
        ChangeHotkeyBtn.IsEnabled = false;

        _appState.HotKeyManager.OnHotkeyCaptured += OnHotkeyCaptured;
        _appState.HotKeyManager.StartCapturingHotkey();
    }

    private void OnHotkeyCaptured(System.Windows.Input.Key key, System.Windows.Input.ModifierKeys modifiers)
    {
        Dispatcher.Invoke(() =>
        {
            _appState.HotKeyManager.OnHotkeyCaptured -= OnHotkeyCaptured;

            _appState.Config.HotKey = key;
            _appState.Config.HotKeyModifiers = modifiers;
            _appState.HotKeyManager.HotKey = key;
            _appState.HotKeyManager.HotKeyModifiers = modifiers;

            HotkeyText.Text = _appState.HotKeyManager.HotkeyDescription;
            HotkeyHint.Visibility = Visibility.Collapsed;
            ChangeHotkeyBtn.IsEnabled = true;
        });
    }

    private void Setting_Changed(object sender, RoutedEventArgs e)
    {
        if (_loading) return;

        _appState.Config.SoundEffects = SoundEffectsCheck.IsChecked == true;
        _appState.Config.AutoInject = AutoInjectCheck.IsChecked == true;
        _appState.Config.MinimizeToTray = MinimizeToTrayCheck.IsChecked == true;
        _appState.Config.LaunchAtStartup = LaunchAtStartupCheck.IsChecked == true;
        _appState.Config.UseAICleanup = UseAICleanupCheck.IsChecked == true;
        UpdateCleanupDescription();
        _appState.Config.ContextAwareness = ContextAwarenessCheck.IsChecked == true;
        _appState.Config.SmartFormatting = SmartFormattingCheck.IsChecked == true;
        _appState.Config.AutoAddToDictionary = AutoDictionaryCheck.IsChecked == true;
    }

    private void Translation_Changed(object sender, RoutedEventArgs e)
    {
        if (_loading) return;

        _appState.Config.TranslationEnabled = TranslationCheck.IsChecked == true;
        LanguagePanel.Visibility = _appState.Config.TranslationEnabled
            ? Visibility.Visible : Visibility.Collapsed;
    }

    private void LanguageCombo_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || LanguageCombo.SelectedIndex < 0) return;
        _appState.Config.TargetLanguage = AppState.SupportedLanguages[LanguageCombo.SelectedIndex];
    }

    private void TypingSpeed_Changed(object sender, TextChangedEventArgs e)
    {
        if (_loading) return;
        if (int.TryParse(TypingSpeedBox.Text, out int wpm) && wpm > 0)
            _appState.Config.TypingSpeedWpm = wpm;
    }

    private void OpenAIKey_Changed(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _appState.Config.OpenAIApiKey = OpenAIKeyBox.Password;
    }

    private void AnthropicKey_Changed(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _appState.Config.AnthropicApiKey = AnthropicKeyBox.Password;
    }

    private void UpdateCleanupDescription()
    {
        if (CleanupDescription == null) return;
        CleanupDescription.Text = _appState.Config.UseAICleanup
            ? "AI cleanup uses Claude Haiku for intelligent formatting. May occasionally modify your words. Requires Claude API key."
            : "Fast programmatic cleanup: capitalizes, adds punctuation, removes fillers. Your words are never changed.";
    }

    private void ClearData_Click(object sender, RoutedEventArgs e)
    {
        var result = MessageBox.Show(
            "Are you sure you want to delete all transcripts? This cannot be undone.",
            "Clear All Data", MessageBoxButton.YesNo, MessageBoxImage.Warning);

        if (result == MessageBoxResult.Yes)
        {
            _appState.Database.DeleteAll();
            MessageBox.Show("All transcripts deleted.", "Done", MessageBoxButton.OK);
        }
    }
}
