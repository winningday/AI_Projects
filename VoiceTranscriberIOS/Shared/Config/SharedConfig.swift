import Foundation
import Combine

/// Manages all app configuration using App Group UserDefaults so data is shared
/// between the main app and the keyboard extension.
final class SharedConfig: ObservableObject {
    static let shared = SharedConfig()

    /// App Group identifier — must match in both targets' entitlements
    static let appGroupID = "group.com.verbalize.ios"

    /// Shared UserDefaults using App Group container
    private let defaults: UserDefaults

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let playSoundEffects = "playSoundEffects"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let privacyMode = "privacyMode"
        static let smartFormatting = "smartFormatting"
        static let autoAddToDictionary = "autoAddToDictionary"
        static let dictionaryEntries = "dictionaryEntries"
        static let styleProfiles = "styleProfiles"
        static let translationEnabled = "translationEnabled"
        static let targetLanguage = "targetLanguage"
        static let typingSpeed = "typingSpeed"
        static let corrections = "corrections"
        static let defaultStyleTone = "defaultStyleTone"
    }

    // MARK: - API Key Storage Keys

    private enum APIKeys {
        static let openAI = "stored_openai_api_key"
        static let claude = "stored_claude_api_key"
    }

    // MARK: - Published Properties

    @Published var playSoundEffects: Bool {
        didSet { defaults.set(playSoundEffects, forKey: Keys.playSoundEffects) }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    @Published var privacyMode: Bool {
        didSet { defaults.set(privacyMode, forKey: Keys.privacyMode) }
    }

    @Published var smartFormatting: Bool {
        didSet { defaults.set(smartFormatting, forKey: Keys.smartFormatting) }
    }

    @Published var autoAddToDictionary: Bool {
        didSet { defaults.set(autoAddToDictionary, forKey: Keys.autoAddToDictionary) }
    }

    @Published var translationEnabled: Bool {
        didSet { defaults.set(translationEnabled, forKey: Keys.translationEnabled) }
    }

    @Published var targetLanguage: String {
        didSet { defaults.set(targetLanguage, forKey: Keys.targetLanguage) }
    }

    @Published var typingSpeed: Int {
        didSet { defaults.set(typingSpeed, forKey: Keys.typingSpeed) }
    }

    @Published var defaultStyleTone: StyleTone {
        didSet { defaults.set(defaultStyleTone.rawValue, forKey: Keys.defaultStyleTone) }
    }

    static let supportedLanguages: [(code: String, name: String)] = [
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("zh", "Chinese (Simplified)"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("ar", "Arabic"),
        ("ru", "Russian"),
        ("hi", "Hindi"),
        ("nl", "Dutch"),
        ("sv", "Swedish"),
        ("pl", "Polish"),
        ("tr", "Turkish"),
        ("vi", "Vietnamese"),
        ("th", "Thai"),
        ("he", "Hebrew"),
        ("uk", "Ukrainian"),
    ]

    // MARK: - Corrections (self-learning)

    @Published var corrections: [WordCorrection] = [] {
        didSet { saveCorrections() }
    }

    /// Recent corrections for inclusion in Claude prompts (last 30)
    var recentCorrections: [WordCorrection] {
        Array(corrections.suffix(30))
    }

    // MARK: - Dictionary

    @Published var dictionaryEntries: [DictionaryEntry] = [] {
        didSet { saveDictionaryEntries() }
    }

    /// All dictionary words as a simple string array (for Whisper prompt)
    var dictionaryWords: [String] {
        dictionaryEntries.map { $0.word }
    }

    // MARK: - Style Profiles

    @Published var styleProfiles: [String: String] = [:] {
        didSet { saveStyleProfiles() }
    }

    func styleTone(for context: StyleContext) -> StyleTone {
        if let raw = styleProfiles[context.rawValue],
           let tone = StyleTone(rawValue: raw) {
            return tone
        }
        switch context {
        case .personalMessages: return .casual
        case .workMessages: return .formal
        case .email: return .formal
        case .other: return .formal
        }
    }

    func setStyleTone(_ tone: StyleTone, for context: StyleContext) {
        styleProfiles[context.rawValue] = tone.rawValue
    }

    // MARK: - Init

    private init() {
        // Use App Group UserDefaults for sharing between app and keyboard extension
        self.defaults = UserDefaults(suiteName: Self.appGroupID) ?? .standard

        self.playSoundEffects = defaults.object(forKey: Keys.playSoundEffects) as? Bool ?? true
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        self.privacyMode = defaults.object(forKey: Keys.privacyMode) as? Bool ?? true
        self.smartFormatting = defaults.object(forKey: Keys.smartFormatting) as? Bool ?? true
        self.autoAddToDictionary = defaults.object(forKey: Keys.autoAddToDictionary) as? Bool ?? true
        self.translationEnabled = defaults.bool(forKey: Keys.translationEnabled)
        self.targetLanguage = defaults.string(forKey: Keys.targetLanguage) ?? "en"
        let savedTypingSpeed = defaults.integer(forKey: Keys.typingSpeed)
        self.typingSpeed = savedTypingSpeed > 0 ? savedTypingSpeed : 40
        if let raw = defaults.string(forKey: Keys.defaultStyleTone),
           let tone = StyleTone(rawValue: raw) {
            self.defaultStyleTone = tone
        } else {
            self.defaultStyleTone = .casual
        }

        // Load dictionary
        if let data = defaults.data(forKey: Keys.dictionaryEntries),
           let entries = try? JSONDecoder().decode([DictionaryEntry].self, from: data) {
            self.dictionaryEntries = entries
        }

        // Load corrections
        if let data = defaults.data(forKey: Keys.corrections),
           let saved = try? JSONDecoder().decode([WordCorrection].self, from: data) {
            self.corrections = saved
        }

        // Load style profiles
        if let data = defaults.data(forKey: Keys.styleProfiles),
           let profiles = try? JSONDecoder().decode([String: String].self, from: data) {
            self.styleProfiles = profiles
        }
    }

    // MARK: - Dictionary Persistence

    private func saveDictionaryEntries() {
        if let data = try? JSONEncoder().encode(dictionaryEntries) {
            defaults.set(data, forKey: Keys.dictionaryEntries)
        }
    }

    func addDictionaryWord(_ word: String, autoAdded: Bool = false) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !dictionaryEntries.contains(where: { $0.word.lowercased() == trimmed.lowercased() }) else { return }
        dictionaryEntries.append(DictionaryEntry(word: trimmed, autoAdded: autoAdded))
    }

    func removeDictionaryWord(at offsets: IndexSet) {
        dictionaryEntries.remove(atOffsets: offsets)
    }

    func removeDictionaryEntry(_ entry: DictionaryEntry) {
        dictionaryEntries.removeAll { $0.id == entry.id }
    }

    // MARK: - Corrections Persistence

    private func saveCorrections() {
        if let data = try? JSONEncoder().encode(corrections) {
            defaults.set(data, forKey: Keys.corrections)
        }
    }

    func addCorrections(_ newCorrections: [WordCorrection]) {
        for correction in newCorrections {
            let exists = corrections.contains {
                $0.original.lowercased() == correction.original.lowercased() &&
                $0.corrected.lowercased() == correction.corrected.lowercased()
            }
            if !exists {
                corrections.append(correction)
            }
        }
        if corrections.count > 200 {
            corrections = Array(corrections.suffix(200))
        }
    }

    func clearCorrections() {
        corrections = []
    }

    // MARK: - Style Persistence

    private func saveStyleProfiles() {
        if let data = try? JSONEncoder().encode(styleProfiles) {
            defaults.set(data, forKey: Keys.styleProfiles)
        }
    }

    // MARK: - API Key Management (App Group UserDefaults)

    var openAIAPIKey: String? {
        get {
            let stored = defaults.string(forKey: APIKeys.openAI)
            if let stored, !stored.isEmpty { return deobfuscate(stored) }
            return ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        }
        set {
            if let value = newValue, !value.isEmpty {
                defaults.set(obfuscate(value), forKey: APIKeys.openAI)
            } else {
                defaults.removeObject(forKey: APIKeys.openAI)
            }
            objectWillChange.send()
        }
    }

    var claudeAPIKey: String? {
        get {
            let stored = defaults.string(forKey: APIKeys.claude)
            if let stored, !stored.isEmpty { return deobfuscate(stored) }
            return ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
        }
        set {
            if let value = newValue, !value.isEmpty {
                defaults.set(obfuscate(value), forKey: APIKeys.claude)
            } else {
                defaults.removeObject(forKey: APIKeys.claude)
            }
            objectWillChange.send()
        }
    }

    var hasAPIKeys: Bool {
        openAIAPIKey != nil && claudeAPIKey != nil &&
        !(openAIAPIKey?.isEmpty ?? true) && !(claudeAPIKey?.isEmpty ?? true)
    }

    // MARK: - Simple Obfuscation (base64 encoding to avoid plain-text in plist)

    private func obfuscate(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
    }

    private func deobfuscate(_ value: String) -> String? {
        guard let data = Data(base64Encoded: value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Force reload from disk (useful when keyboard extension starts and app may have changed settings)
    func reload() {
        defaults.synchronize()

        if let data = defaults.data(forKey: Keys.dictionaryEntries),
           let entries = try? JSONDecoder().decode([DictionaryEntry].self, from: data) {
            self.dictionaryEntries = entries
        }

        if let data = defaults.data(forKey: Keys.corrections),
           let saved = try? JSONDecoder().decode([WordCorrection].self, from: data) {
            self.corrections = saved
        }

        self.translationEnabled = defaults.bool(forKey: Keys.translationEnabled)
        self.targetLanguage = defaults.string(forKey: Keys.targetLanguage) ?? "en"
        self.smartFormatting = defaults.object(forKey: Keys.smartFormatting) as? Bool ?? true
        self.autoAddToDictionary = defaults.object(forKey: Keys.autoAddToDictionary) as? Bool ?? true

        if let raw = defaults.string(forKey: Keys.defaultStyleTone),
           let tone = StyleTone(rawValue: raw) {
            self.defaultStyleTone = tone
        }

        if let data = defaults.data(forKey: Keys.styleProfiles),
           let profiles = try? JSONDecoder().decode([String: String].self, from: data) {
            self.styleProfiles = profiles
        }
    }
}
