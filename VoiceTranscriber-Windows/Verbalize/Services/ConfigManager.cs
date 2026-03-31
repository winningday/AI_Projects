// Module: Configuration persistence — stores settings, API keys, dictionary, corrections
using System.Text.Json;
using System.Windows.Input;
using Verbalize.Models;

namespace Verbalize.Services;

public class ConfigManager
{
    private static readonly string ConfigDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Verbalize");
    private static readonly string ConfigFile = Path.Combine(ConfigDir, "settings.json");

    private ConfigData _data = new();

    // API Keys
    public string OpenAIApiKey
    {
        get => Deobfuscate(_data.OpenAIApiKeyObf);
        set { _data.OpenAIApiKeyObf = Obfuscate(value); Save(); }
    }

    public string AnthropicApiKey
    {
        get => Deobfuscate(_data.AnthropicApiKeyObf);
        set { _data.AnthropicApiKeyObf = Obfuscate(value); Save(); }
    }

    // Hotkey
    public Key HotKey
    {
        get => _data.HotKey;
        set { _data.HotKey = value; Save(); }
    }

    public ModifierKeys HotKeyModifiers
    {
        get => _data.HotKeyModifiers;
        set { _data.HotKeyModifiers = value; Save(); }
    }

    // General settings
    public bool SoundEffects
    {
        get => _data.SoundEffects;
        set { _data.SoundEffects = value; Save(); }
    }

    public bool AutoInject
    {
        get => _data.AutoInject;
        set { _data.AutoInject = value; Save(); }
    }

    public bool ContextAwareness
    {
        get => _data.ContextAwareness;
        set { _data.ContextAwareness = value; Save(); }
    }

    public bool SmartFormatting
    {
        get => _data.SmartFormatting;
        set { _data.SmartFormatting = value; Save(); }
    }

    public bool AutoAddToDictionary
    {
        get => _data.AutoAddToDictionary;
        set { _data.AutoAddToDictionary = value; Save(); }
    }

    public int TypingSpeedWpm
    {
        get => _data.TypingSpeedWpm;
        set { _data.TypingSpeedWpm = value; Save(); }
    }

    public bool LaunchAtStartup
    {
        get => _data.LaunchAtStartup;
        set { _data.LaunchAtStartup = value; Save(); }
    }

    public bool MinimizeToTray
    {
        get => _data.MinimizeToTray;
        set { _data.MinimizeToTray = value; Save(); }
    }

    // Translation
    public bool TranslationEnabled
    {
        get => _data.TranslationEnabled;
        set { _data.TranslationEnabled = value; Save(); }
    }

    public string TargetLanguage
    {
        get => _data.TargetLanguage;
        set { _data.TargetLanguage = value; Save(); }
    }

    // Dictionary
    public List<DictionaryEntry> DictionaryEntries
    {
        get => _data.DictionaryEntries;
        set { _data.DictionaryEntries = value; Save(); }
    }

    // Corrections
    public List<WordCorrection> Corrections
    {
        get => _data.Corrections;
        set { _data.Corrections = value; Save(); }
    }

    // Style profiles
    public Dictionary<string, string> StyleProfiles
    {
        get => _data.StyleProfiles;
        set { _data.StyleProfiles = value; Save(); }
    }

    // Stats
    public int TotalWords
    {
        get => _data.TotalWords;
        set { _data.TotalWords = value; Save(); }
    }

    public double TotalRecordingTime
    {
        get => _data.TotalRecordingTime;
        set { _data.TotalRecordingTime = value; Save(); }
    }

    public bool HasCompletedOnboarding
    {
        get => _data.HasCompletedOnboarding;
        set { _data.HasCompletedOnboarding = value; Save(); }
    }

    // AI cleanup toggle (default: true — uses Claude for intelligent formatting)
    public bool UseAICleanup
    {
        get => _data.UseAICleanup;
        set { _data.UseAICleanup = value; Save(); }
    }

    // Transcription engine
    public TranscriptionEngine TranscriptionEngine
    {
        get => _data.TranscriptionEngine;
        set { _data.TranscriptionEngine = value; Save(); }
    }

    // Deepgram API key
    public string DeepgramApiKey
    {
        get => Deobfuscate(_data.DeepgramApiKeyObf);
        set { _data.DeepgramApiKeyObf = Obfuscate(value); Save(); }
    }

    // Mistral API key
    public string MistralApiKey
    {
        get => Deobfuscate(_data.MistralApiKeyObf);
        set { _data.MistralApiKeyObf = Obfuscate(value); Save(); }
    }

    public ConfigManager()
    {
        Load();

        // Check environment variables as fallback for API keys
        if (string.IsNullOrEmpty(_data.OpenAIApiKeyObf))
        {
            var envKey = Environment.GetEnvironmentVariable("OPENAI_API_KEY");
            if (!string.IsNullOrEmpty(envKey))
                _data.OpenAIApiKeyObf = Obfuscate(envKey);
        }
        if (string.IsNullOrEmpty(_data.AnthropicApiKeyObf))
        {
            var envKey = Environment.GetEnvironmentVariable("ANTHROPIC_API_KEY");
            if (!string.IsNullOrEmpty(envKey))
                _data.AnthropicApiKeyObf = Obfuscate(envKey);
        }
    }

    public void AddDictionaryEntry(string word, string source = "manual")
    {
        if (_data.DictionaryEntries.Any(e => e.Word.Equals(word, StringComparison.OrdinalIgnoreCase)))
            return;

        _data.DictionaryEntries.Add(new DictionaryEntry
        {
            Word = word,
            Source = source,
            AddedDate = DateTime.UtcNow
        });
        Save();
    }

    public void RemoveDictionaryEntry(string word)
    {
        _data.DictionaryEntries.RemoveAll(e => e.Word.Equals(word, StringComparison.OrdinalIgnoreCase));
        Save();
    }

    public void AddCorrection(string wrong, string right)
    {
        if (_data.Corrections.Any(c => c.Wrong == wrong && c.Right == right))
            return;

        _data.Corrections.Add(new WordCorrection
        {
            Wrong = wrong,
            Right = right,
            Timestamp = DateTime.UtcNow
        });

        // Cap at 200
        if (_data.Corrections.Count > 200)
            _data.Corrections = _data.Corrections.TakeLast(200).ToList();

        Save();
    }

    public StyleTone GetStyleForContext(ContextType context)
    {
        var key = context.ToString();
        if (_data.StyleProfiles.TryGetValue(key, out var value) &&
            Enum.TryParse<StyleTone>(value, out var tone))
            return tone;

        return context switch
        {
            ContextType.PersonalMessages => StyleTone.Casual,
            ContextType.WorkMessages => StyleTone.Formal,
            ContextType.Email => StyleTone.Formal,
            _ => StyleTone.Casual
        };
    }

    public void SetStyleForContext(ContextType context, StyleTone tone)
    {
        _data.StyleProfiles[context.ToString()] = tone.ToString();
        Save();
    }

    private void Load()
    {
        try
        {
            if (File.Exists(ConfigFile))
            {
                var json = File.ReadAllText(ConfigFile);
                _data = JsonSerializer.Deserialize<ConfigData>(json) ?? new ConfigData();
            }
        }
        catch
        {
            _data = new ConfigData();
        }
    }

    private void Save()
    {
        try
        {
            Directory.CreateDirectory(ConfigDir);
            var json = JsonSerializer.Serialize(_data, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(ConfigFile, json);
        }
        catch { /* ignore save failures */ }
    }

    // Simple Base64 obfuscation (not encryption — just prevents casual viewing)
    private static string Obfuscate(string value) =>
        string.IsNullOrEmpty(value) ? "" : Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(value));

    private static string Deobfuscate(string value)
    {
        if (string.IsNullOrEmpty(value)) return "";
        try { return System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(value)); }
        catch { return ""; }
    }

    private class ConfigData
    {
        public string OpenAIApiKeyObf { get; set; } = "";
        public string AnthropicApiKeyObf { get; set; } = "";
        public Key HotKey { get; set; } = Key.F8;
        public ModifierKeys HotKeyModifiers { get; set; } = ModifierKeys.None;
        public bool SoundEffects { get; set; } = true;
        public bool AutoInject { get; set; } = true;
        public bool ContextAwareness { get; set; } = true;
        public bool SmartFormatting { get; set; } = true;
        public bool AutoAddToDictionary { get; set; } = true;
        public int TypingSpeedWpm { get; set; } = 40;
        public bool LaunchAtStartup { get; set; } = false;
        public bool MinimizeToTray { get; set; } = true;
        public bool TranslationEnabled { get; set; } = false;
        public string TargetLanguage { get; set; } = "English";
        public List<DictionaryEntry> DictionaryEntries { get; set; } = new();
        public List<WordCorrection> Corrections { get; set; } = new();
        public Dictionary<string, string> StyleProfiles { get; set; } = new();
        public int TotalWords { get; set; }
        public double TotalRecordingTime { get; set; }
        public bool HasCompletedOnboarding { get; set; } = false;
        public bool UseAICleanup { get; set; } = true;
        public TranscriptionEngine TranscriptionEngine { get; set; } = TranscriptionEngine.WhisperMini;
        public string DeepgramApiKeyObf { get; set; } = "";
        public string MistralApiKeyObf { get; set; } = "";
    }
}
