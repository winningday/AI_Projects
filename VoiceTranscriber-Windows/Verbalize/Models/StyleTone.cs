namespace Verbalize.Models;

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
