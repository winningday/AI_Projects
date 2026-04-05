namespace Verbalize.Models;

/// <summary>Transcription engine choice.</summary>
public enum TranscriptionEngine
{
    WhisperMini,
    WhisperFull,
    Deepgram,
    Mistral,
    CohereTranscribe
}

public static class TranscriptionEngineExtensions
{
    public static string DisplayName(this TranscriptionEngine engine) => engine switch
    {
        TranscriptionEngine.WhisperMini => "OpenAI Whisper (Fast)",
        TranscriptionEngine.WhisperFull => "OpenAI Whisper (Accurate)",
        TranscriptionEngine.Deepgram => "Deepgram Nova-2",
        TranscriptionEngine.Mistral => "Mistral Voxtral",
        TranscriptionEngine.CohereTranscribe => "Cohere Transcribe",
        _ => "OpenAI Whisper (Fast)"
    };

    public static string Subtitle(this TranscriptionEngine engine) => engine switch
    {
        TranscriptionEngine.WhisperMini => "gpt-4o-mini-transcribe — fast, good accuracy",
        TranscriptionEngine.WhisperFull => "gpt-4o-transcribe — best accuracy, slightly slower",
        TranscriptionEngine.Deepgram => "Nova-2 — very fast, great accuracy",
        TranscriptionEngine.Mistral => "Voxtral Mini — fast, accurate, $0.003/min",
        TranscriptionEngine.CohereTranscribe => "Best accuracy (5.42% WER), free API",
        _ => ""
    };
}

/// <summary>Which AI model to use for transcript cleanup.</summary>
public enum CleanupModel
{
    ClaudeHaiku,
    Gpt4oMini
}

public static class CleanupModelExtensions
{
    public static string DisplayName(this CleanupModel model) => model switch
    {
        CleanupModel.ClaudeHaiku => "Claude Haiku",
        CleanupModel.Gpt4oMini => "GPT-4o-mini",
        _ => "GPT-4o-mini"
    };

    public static string Subtitle(this CleanupModel model) => model switch
    {
        CleanupModel.ClaudeHaiku => "Good quality, requires Claude key",
        CleanupModel.Gpt4oMini => "Very fast, uses OpenAI key",
        _ => ""
    };
}

public enum StyleTone
{
    Formal,
    Casual,
    VeryCasual,
    Excited
}

public enum ContextType
{
    PersonalMessages,
    WorkMessages,
    Email,
    Other
}

public static class StyleToneExtensions
{
    public static string DisplayName(this StyleTone tone) => tone switch
    {
        StyleTone.Formal => "Formal",
        StyleTone.Casual => "Casual",
        StyleTone.VeryCasual => "Very Casual",
        StyleTone.Excited => "Excited",
        _ => "Casual"
    };

    public static string Description(this StyleTone tone) => tone switch
    {
        StyleTone.Formal => "Professional, complete sentences, proper grammar",
        StyleTone.Casual => "Natural, conversational, contractions allowed",
        StyleTone.VeryCasual => "Relaxed, lowercase ok, abbreviations ok",
        StyleTone.Excited => "Enthusiastic, expressive, exclamation marks",
        _ => ""
    };

    public static string Example(this StyleTone tone) => tone switch
    {
        StyleTone.Formal => "I would be happy to assist you with that request.",
        StyleTone.Casual => "Sure, I can help you with that!",
        StyleTone.VeryCasual => "yeah totally, i got you",
        StyleTone.Excited => "Oh absolutely! I'd LOVE to help with that!",
        _ => ""
    };

    public static string PromptInstructions(this StyleTone tone) => tone switch
    {
        StyleTone.Formal => "Use proper capitalization, full punctuation, and complete sentences. Preserve ALL content — every sentence and idea from the input must appear in the output. Do not summarize or condense.",
        StyleTone.Casual => "Use proper capitalization but minimal punctuation. Skip periods at the end of short messages. Keep contractions. Preserve ALL content — every sentence and idea from the input must appear in the output. Do not summarize or condense.",
        StyleTone.VeryCasual => "Use all lowercase. Minimal punctuation. Skip periods. Keep it natural, like texting. Preserve ALL content — every sentence and idea from the input must appear in the output. Do not summarize, condense, or shorten.",
        StyleTone.Excited => "Use proper capitalization. Add exclamation marks for emphasis. Keep energy high. Preserve ALL content — every sentence and idea from the input must appear in the output. Do not summarize or condense.",
        _ => ""
    };
}
