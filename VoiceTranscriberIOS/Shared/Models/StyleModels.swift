import Foundation

/// Which AI model to use for transcript cleanup.
enum CleanupModel: String, CaseIterable, Codable, Identifiable {
    case claudeHaiku = "claude_haiku"
    case gpt4oMini = "gpt4o_mini"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeHaiku: return "Claude Haiku"
        case .gpt4oMini: return "GPT-4o-mini"
        }
    }

    var subtitle: String {
        switch self {
        case .claudeHaiku: return "Good quality, requires Claude key"
        case .gpt4oMini: return "Very fast, uses OpenAI key"
        }
    }
}

/// Transcription engine choice.
enum TranscriptionEngine: String, CaseIterable, Codable, Identifiable {
    case whisperMini = "whisper_mini"
    case whisperFull = "whisper_full"
    case deepgram = "deepgram"
    case mistral = "mistral"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisperMini: return "OpenAI Whisper (Fast)"
        case .whisperFull: return "OpenAI Whisper (Accurate)"
        case .deepgram: return "Deepgram Nova-2"
        case .mistral: return "Mistral Voxtral"
        }
    }

    var subtitle: String {
        switch self {
        case .whisperMini: return "gpt-4o-mini-transcribe — fast, good accuracy"
        case .whisperFull: return "gpt-4o-transcribe — best accuracy, slightly slower"
        case .deepgram: return "Nova-2 — very fast, great accuracy"
        case .mistral: return "Voxtral Mini — fast, accurate, $0.003/min"
        }
    }

    var requiredKeyType: RequiredKeyType {
        switch self {
        case .whisperMini, .whisperFull: return .openAI
        case .deepgram: return .deepgram
        case .mistral: return .mistral
        }
    }
}

enum RequiredKeyType {
    case openAI, claude, deepgram, mistral, none
}

/// Style profile for different message contexts.
enum StyleContext: String, CaseIterable, Codable, Identifiable {
    case personalMessages = "personal"
    case workMessages = "work"
    case email = "email"
    case other = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .personalMessages: return "Personal Messages"
        case .workMessages: return "Work Messages"
        case .email: return "Email"
        case .other: return "Other"
        }
    }

    var description: String {
        switch self {
        case .personalMessages: return "iMessage, WhatsApp, Telegram, etc."
        case .workMessages: return "Slack, Teams, Discord, etc."
        case .email: return "Mail, Gmail, Outlook, etc."
        case .other: return "Notes, documents, other apps"
        }
    }
}

/// Style tone for text output.
enum StyleTone: String, CaseIterable, Codable, Identifiable {
    case formal = "formal"
    case casual = "casual"
    case veryCasual = "very_casual"
    case excited = "excited"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .formal: return "Formal."
        case .casual: return "Casual"
        case .veryCasual: return "very casual"
        case .excited: return "Excited!"
        }
    }

    var subtitle: String {
        switch self {
        case .formal: return "Caps + Punctuation"
        case .casual: return "Caps + Less punctuation"
        case .veryCasual: return "No Caps + Less punctuation"
        case .excited: return "More exclamations"
        }
    }

    var example: String {
        switch self {
        case .formal: return "Hey, are you free for lunch tomorrow? Let's do 12 if that works for you."
        case .casual: return "Hey are you free for lunch tomorrow? Let's do 12 if that works for you"
        case .veryCasual: return "hey are you free for lunch tomorrow? let's do 12 if that works for you"
        case .excited: return "Hey, are you free for lunch tomorrow? Let's do 12 if that works for you!"
        }
    }

    /// Instructions for Claude prompt
    var promptInstructions: String {
        switch self {
        case .formal:
            return "Use proper capitalization, full punctuation, and complete sentences. Preserve ALL content — every sentence and idea from the input must appear in the output. Do not summarize or condense."
        case .casual:
            return "Use proper capitalization but minimal punctuation. Skip periods at the end of short messages. Keep contractions. Preserve ALL content — every sentence and idea from the input must appear in the output. Do not summarize or condense."
        case .veryCasual:
            return "Use all lowercase. Minimal punctuation. Skip periods. Keep it natural, like texting. Preserve ALL content — every sentence and idea from the input must appear in the output. Do not summarize, condense, or shorten."
        case .excited:
            return "Use proper capitalization. Add exclamation marks for emphasis. Keep energy high. Preserve ALL content — every sentence and idea from the input must appear in the output. Do not summarize or condense."
        }
    }
}

/// A custom dictionary word entry.
struct DictionaryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var word: String
    var autoAdded: Bool
    var dateAdded: Date

    init(id: UUID = UUID(), word: String, autoAdded: Bool = false, dateAdded: Date = Date()) {
        self.id = id
        self.word = word
        self.autoAdded = autoAdded
        self.dateAdded = dateAdded
    }
}

/// A single word-level correction detected from user edits.
struct WordCorrection: Codable, Equatable, Identifiable {
    let id: UUID
    let original: String
    let corrected: String
    let date: Date

    init(id: UUID = UUID(), original: String, corrected: String, date: Date = Date()) {
        self.id = id
        self.original = original
        self.corrected = corrected
        self.date = date
    }
}
