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
}
