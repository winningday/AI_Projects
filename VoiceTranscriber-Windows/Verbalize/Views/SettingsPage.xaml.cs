using System.Windows;
using System.Windows.Controls;
using Verbalize.Models;
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
        // Transcription engine
        switch (_appState.Config.TranscriptionEngine)
        {
            case TranscriptionEngine.WhisperMini: EngineWhisperMini.IsChecked = true; break;
            case TranscriptionEngine.WhisperFull: EngineWhisperFull.IsChecked = true; break;
            case TranscriptionEngine.Deepgram: EngineDeepgram.IsChecked = true; break;
            case TranscriptionEngine.Mistral: EngineMistral.IsChecked = true; break;
            default: EngineWhisperMini.IsChecked = true; break;
        }

        UseAICleanupCheck.IsChecked = _appState.Config.UseAICleanup;
        UpdateCleanupDescription();
        // Cleanup model
        switch (_appState.Config.CleanupModel)
        {
            case CleanupModel.Gpt4oMini: CleanupGpt4oMini.IsChecked = true; break;
            case CleanupModel.ClaudeHaiku: CleanupClaudeHaiku.IsChecked = true; break;
            default: CleanupGpt4oMini.IsChecked = true; break;
        }
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
        if (!string.IsNullOrEmpty(_appState.Config.DeepgramApiKey))
            DeepgramKeyBox.Password = _appState.Config.DeepgramApiKey;
        if (!string.IsNullOrEmpty(_appState.Config.MistralApiKey))
            MistralKeyBox.Password = _appState.Config.MistralApiKey;

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

    private void Engine_Changed(object sender, RoutedEventArgs e)
    {
        if (_loading) return;

        if (EngineWhisperMini.IsChecked == true)
            _appState.Config.TranscriptionEngine = TranscriptionEngine.WhisperMini;
        else if (EngineWhisperFull.IsChecked == true)
            _appState.Config.TranscriptionEngine = TranscriptionEngine.WhisperFull;
        else if (EngineDeepgram.IsChecked == true)
            _appState.Config.TranscriptionEngine = TranscriptionEngine.Deepgram;
        else if (EngineMistral.IsChecked == true)
            _appState.Config.TranscriptionEngine = TranscriptionEngine.Mistral;
    }

    private void DeepgramKey_Changed(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _appState.Config.DeepgramApiKey = DeepgramKeyBox.Password;
    }

    private void MistralKey_Changed(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _appState.Config.MistralApiKey = MistralKeyBox.Password;
    }

    private void CleanupModel_Changed(object sender, RoutedEventArgs e)
    {
        if (_loading) return;

        if (CleanupGpt4oMini.IsChecked == true)
            _appState.Config.CleanupModel = CleanupModel.Gpt4oMini;
        else if (CleanupClaudeHaiku.IsChecked == true)
            _appState.Config.CleanupModel = CleanupModel.ClaudeHaiku;
    }

    private void UpdateCleanupDescription()
    {
        if (CleanupDescription == null) return;
        CleanupDescription.Text = _appState.Config.UseAICleanup
            ? "AI cleanup uses an LLM for intelligent formatting. Choose your preferred model below."
            : "Fast programmatic cleanup: capitalizes, adds punctuation, removes fillers. Your words are never changed.";
        if (CleanupModelPanel != null)
            CleanupModelPanel.Visibility = _appState.Config.UseAICleanup
                ? Visibility.Visible : Visibility.Collapsed;
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
