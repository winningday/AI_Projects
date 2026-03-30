// Module: Central app orchestrator — manages recording pipeline, state, and coordinates all services
using System.ComponentModel;
using System.Media;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Input;
using Verbalize.Models;

namespace Verbalize.Services;

public class AppState : INotifyPropertyChanged, IDisposable
{
    private static AppState? _instance;
    public static AppState Instance => _instance ??= new AppState();

    // Services
    public AudioRecorder AudioRecorder { get; } = new();
    public HotKeyManager HotKeyManager { get; } = new();
    public WhisperClient WhisperClient { get; } = new();
    public ClaudeClient ClaudeClient { get; } = new();
    public DeepgramClient DeepgramClient { get; } = new();
    public ConfigManager Config { get; } = new();
    public TranscriptDatabase Database { get; } = new();
    public CorrectionTracker CorrectionTracker { get; private set; }

    // State
    private AppStatus _status = AppStatus.Idle;
    public AppStatus Status
    {
        get => _status;
        set { _status = value; OnPropertyChanged(); OnPropertyChanged(nameof(StatusText)); }
    }

    private string _lastTranscript = string.Empty;
    public string LastTranscript
    {
        get => _lastTranscript;
        set { _lastTranscript = value; OnPropertyChanged(); }
    }

    private string? _errorMessage;
    public string? ErrorMessage
    {
        get => _errorMessage;
        set { _errorMessage = value; OnPropertyChanged(); OnPropertyChanged(nameof(HasError)); }
    }

    public bool HasError => !string.IsNullOrEmpty(ErrorMessage);

    public string StatusText => Status switch
    {
        AppStatus.Idle => "Ready",
        AppStatus.Recording => "Recording...",
        AppStatus.Processing => "Processing...",
        AppStatus.Error => ErrorMessage ?? "Error",
        _ => "Ready"
    };

    // Stats (computed from config)
    public int TotalWords => Config.TotalWords;
    public double TotalRecordingTime => Config.TotalRecordingTime;

    // Supported languages for translation
    public static readonly string[] SupportedLanguages = {
        "English", "Spanish", "French", "German", "Italian", "Portuguese",
        "Chinese", "Japanese", "Korean", "Arabic", "Russian", "Hindi",
        "Dutch", "Swedish", "Polish", "Turkish", "Vietnamese", "Thai",
        "Hebrew", "Ukrainian"
    };

    // Recording overlay window
    public event Action? RecordingStarted;
    public event Action? RecordingStopped;
    public event Action? TranscriptionCompleted;

    private string? _capturedAppName;

    private AppState()
    {
        CorrectionTracker = new CorrectionTracker(Config);

        // Configure hotkey from saved settings
        HotKeyManager.HotKey = Config.HotKey;
        HotKeyManager.HotKeyModifiers = Config.HotKeyModifiers;

        // Wire up hotkey events
        HotKeyManager.OnHotkeyDown += OnHotkeyDown;
        HotKeyManager.OnHotkeyUp += OnHotkeyUp;
        HotKeyManager.OnHotkeyCaptured += OnHotkeyCaptured;

        // Start listening
        try
        {
            HotKeyManager.StartListening();
        }
        catch (Exception ex)
        {
            ErrorMessage = $"Failed to register hotkey: {ex.Message}";
        }
    }

    private void OnHotkeyDown()
    {
        if (Status == AppStatus.Recording || Status == AppStatus.Processing) return;

        Application.Current.Dispatcher.Invoke(() =>
        {
            StartRecording();
        });
    }

    private void OnHotkeyUp()
    {
        if (Status != AppStatus.Recording) return;

        Application.Current.Dispatcher.Invoke(() =>
        {
            StopRecordingAndProcess();
        });
    }

    private void OnHotkeyCaptured(Key key, ModifierKeys modifiers)
    {
        Application.Current.Dispatcher.Invoke(() =>
        {
            Config.HotKey = key;
            Config.HotKeyModifiers = modifiers;
            HotKeyManager.HotKey = key;
            HotKeyManager.HotKeyModifiers = modifiers;
            OnPropertyChanged(nameof(Config));
        });
    }

    public void StartRecording()
    {
        ErrorMessage = null;

        // Validate API keys based on selected engine
        var engine = Config.TranscriptionEngine;
        if ((engine == TranscriptionEngine.WhisperMini || engine == TranscriptionEngine.WhisperFull)
            && string.IsNullOrEmpty(Config.OpenAIApiKey))
        {
            ErrorMessage = "OpenAI API key not set. Go to Settings to configure.";
            Status = AppStatus.Error;
            return;
        }
        if ((Config.UseAICleanup || Config.TranslationEnabled)
            && string.IsNullOrEmpty(Config.AnthropicApiKey))
        {
            ErrorMessage = "Claude API key not set. Go to Settings to configure.";
            Status = AppStatus.Error;
            return;
        }
        if (engine == TranscriptionEngine.Deepgram && string.IsNullOrEmpty(Config.DeepgramApiKey))
        {
            ErrorMessage = "Deepgram API key not set. Go to Settings to configure.";
            Status = AppStatus.Error;
            return;
        }

        // Capture active app before recording
        _capturedAppName = Config.ContextAwareness ? TextInjector.GetActiveProcessName() : null;

        Status = AppStatus.Recording;
        AudioRecorder.StartRecording();

        if (Config.SoundEffects)
            SystemSounds.Beep.Play();

        RecordingStarted?.Invoke();
    }

    public async void StopRecordingAndProcess()
    {
        if (Status != AppStatus.Recording) return;

        var (filePath, duration) = AudioRecorder.StopRecording();

        if (Config.SoundEffects)
            SystemSounds.Beep.Play();

        RecordingStopped?.Invoke();

        if (string.IsNullOrEmpty(filePath) || duration < 0.3)
        {
            Status = AppStatus.Idle;
            return;
        }

        Status = AppStatus.Processing;

        try
        {
            await ProcessRecordingAsync(filePath, duration);
        }
        catch (Exception ex)
        {
            ErrorMessage = $"Processing failed: {ex.Message}";
            Status = AppStatus.Error;

            // Auto-clear error after 5 seconds
            _ = Task.Run(async () =>
            {
                await Task.Delay(5000);
                Application.Current.Dispatcher.Invoke(() =>
                {
                    if (Status == AppStatus.Error)
                    {
                        ErrorMessage = null;
                        Status = AppStatus.Idle;
                    }
                });
            });
        }
        finally
        {
            AudioRecorder.CleanupTempFile(filePath);
        }
    }

    private async Task ProcessRecordingAsync(string filePath, double duration)
    {
        var pipelineStart = System.Diagnostics.Stopwatch.StartNew();
        var dictionaryWords = Config.DictionaryEntries.Select(e => e.Word).ToList();
        var languageHint = Config.TranslationEnabled ? null : "en";

        // Determine style tone from context
        var tone = StyleTone.Casual;
        if (Config.ContextAwareness && !string.IsNullOrEmpty(_capturedAppName))
        {
            var context = DetectContext(_capturedAppName);
            tone = Config.GetStyleForContext(context);
        }

        string rawText;
        string cleanedText;

        var sttModel = Config.TranscriptionEngine switch
        {
            TranscriptionEngine.WhisperMini => "gpt-4o-mini-transcribe",
            TranscriptionEngine.WhisperFull => "gpt-4o-transcribe",
            TranscriptionEngine.Deepgram => "nova-2",
            TranscriptionEngine.Mistral => "voxtral-mini",
            _ => "gpt-4o-mini-transcribe"
        };

        // Step 1: Transcribe with selected engine
        var transcribeTimer = System.Diagnostics.Stopwatch.StartNew();
        switch (Config.TranscriptionEngine)
        {
            case TranscriptionEngine.WhisperMini:
                rawText = await WhisperClient.TranscribeAsync(filePath, Config.OpenAIApiKey,
                    dictionaryWords, languageHint, model: "gpt-4o-mini-transcribe");
                break;
            case TranscriptionEngine.WhisperFull:
                rawText = await WhisperClient.TranscribeAsync(filePath, Config.OpenAIApiKey,
                    dictionaryWords, languageHint, model: "gpt-4o-transcribe");
                break;
            case TranscriptionEngine.Deepgram:
                rawText = await DeepgramClient.TranscribeAsync(filePath, Config.DeepgramApiKey,
                    dictionaryWords, languageHint);
                break;
            case TranscriptionEngine.Mistral:
                rawText = await MistralClient.TranscribeAsync(filePath, Config.MistralApiKey,
                    dictionaryWords, languageHint);
                break;
            default:
                rawText = await WhisperClient.TranscribeAsync(filePath, Config.OpenAIApiKey,
                    dictionaryWords, languageHint);
                break;
        }
        transcribeTimer.Stop();
        var transcribeMs = (int)transcribeTimer.ElapsedMilliseconds;

        if (string.IsNullOrWhiteSpace(rawText))
        {
            PipelineLogger.Log(Config.TranscriptionEngine.DisplayName(), sttModel, transcribeMs, 0, "none", "", duration, 0, error: "No speech detected");
            Status = AppStatus.Idle;
            return;
        }

        // Step 2: Clean transcript
        var cleanupTimer = System.Diagnostics.Stopwatch.StartNew();
        string cleanupMethod;
        string cleanupModel;
        var needsAICleanup = Config.UseAICleanup || Config.TranslationEnabled;
        if (needsAICleanup && !string.IsNullOrEmpty(Config.AnthropicApiKey))
        {
            cleanedText = await ClaudeClient.CleanTranscriptionAsync(
                rawText, Config.AnthropicApiKey, tone, dictionaryWords,
                Config.Corrections, null, _capturedAppName,
                Config.TranslationEnabled, Config.TargetLanguage);
            cleanupMethod = "claude";
            cleanupModel = "claude-haiku-4-5";
        }
        else
        {
            cleanedText = ProgrammaticCleaner.Clean(rawText, tone);
            cleanupMethod = "programmatic";
            cleanupModel = "none";
        }
        cleanupTimer.Stop();
        var cleanupMs = (int)cleanupTimer.ElapsedMilliseconds;

        if (string.IsNullOrWhiteSpace(cleanedText))
        {
            PipelineLogger.Log(Config.TranscriptionEngine.DisplayName(), sttModel, transcribeMs, cleanupMs, cleanupMethod, cleanupModel, duration, 0, error: "Empty after cleanup");
            Status = AppStatus.Idle;
            return;
        }

        // Step 4: Save transcript
        var transcript = new Transcript
        {
            OriginalText = rawText,
            CleanedText = cleanedText,
            DurationSeconds = duration
        };
        Database.Save(transcript);

        // Step 5: Update stats
        Config.TotalWords += transcript.WordCount;
        Config.TotalRecordingTime += duration;

        // Step 6: Inject text
        if (Config.AutoInject)
        {
            await TextInjector.InjectTextAsync(cleanedText);
            CorrectionTracker.StartTracking(cleanedText);
        }

        pipelineStart.Stop();
        var totalMs = (int)pipelineStart.ElapsedMilliseconds;
        PipelineLogger.Log(Config.TranscriptionEngine.DisplayName(), sttModel, transcribeMs, cleanupMs, cleanupMethod, cleanupModel, duration, transcript.WordCount, totalMs: totalMs);

        LastTranscript = cleanedText;
        Status = AppStatus.Idle;
        TranscriptionCompleted?.Invoke();

        OnPropertyChanged(nameof(TotalWords));
        OnPropertyChanged(nameof(TotalRecordingTime));
    }

    private static ContextType DetectContext(string appName)
    {
        var lower = appName.ToLowerInvariant();

        if (lower.Contains("whatsapp") || lower.Contains("telegram") ||
            lower.Contains("signal") || lower.Contains("messenger") ||
            lower.Contains("imessage"))
            return ContextType.PersonalMessages;

        if (lower.Contains("slack") || lower.Contains("teams") || lower.Contains("discord"))
            return ContextType.WorkMessages;

        if (lower.Contains("outlook") || lower.Contains("gmail") ||
            lower.Contains("thunderbird") || lower.Contains("mail"))
            return ContextType.Email;

        return ContextType.Other;
    }

    public void CancelRecording()
    {
        if (Status == AppStatus.Recording)
        {
            AudioRecorder.StopRecording();
            Status = AppStatus.Idle;
            RecordingStopped?.Invoke();
        }
    }

    public void Dispose()
    {
        HotKeyManager.Dispose();
        AudioRecorder.Dispose();
        Database.Dispose();
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

public enum AppStatus
{
    Idle,
    Recording,
    Processing,
    Error
}
