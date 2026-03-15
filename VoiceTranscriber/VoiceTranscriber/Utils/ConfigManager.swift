import Foundation
import Security
import ServiceManagement

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
        case .other: return "Code editors, notes, documents, etc."
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
            return "Use proper capitalization, full punctuation, and complete sentences."
        case .casual:
            return "Use proper capitalization but minimal punctuation. Skip periods at the end of short messages. Keep contractions."
        case .veryCasual:
            return "Use all lowercase. Minimal punctuation. Skip periods. Keep it brief and natural, like texting."
        case .excited:
            return "Use proper capitalization. Add exclamation marks for emphasis. Keep energy high."
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

/// Manages all app configuration including API keys, preferences, dictionary, and styles.
final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    private let defaults = UserDefaults.standard

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let useHapticFeedback = "useHapticFeedback"
        static let playSoundEffects = "playSoundEffects"
        static let autoInjectText = "autoInjectText"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let launchAtLogin = "launchAtLogin"
        static let privacyMode = "privacyMode"
        static let contextAwareness = "contextAwareness"
        static let smartFormatting = "smartFormatting"
        static let autoAddToDictionary = "autoAddToDictionary"
        static let dictionaryEntries = "dictionaryEntries"
        static let styleProfiles = "styleProfiles"
        static let translationEnabled = "translationEnabled"
        static let targetLanguage = "targetLanguage"
    }

    // MARK: - Keychain Service

    private let keychainService = "com.voicetranscriber.apikeys"

    // MARK: - Published Properties

    @Published var hotkeyKeyCode: UInt16 {
        didSet { defaults.set(Int(hotkeyKeyCode), forKey: Keys.hotkeyKeyCode) }
    }

    @Published var hotkeyModifiers: UInt {
        didSet { defaults.set(hotkeyModifiers, forKey: Keys.hotkeyModifiers) }
    }

    @Published var useHapticFeedback: Bool {
        didSet { defaults.set(useHapticFeedback, forKey: Keys.useHapticFeedback) }
    }

    @Published var playSoundEffects: Bool {
        didSet { defaults.set(playSoundEffects, forKey: Keys.playSoundEffects) }
    }

    @Published var autoInjectText: Bool {
        didSet { defaults.set(autoInjectText, forKey: Keys.autoInjectText) }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            updateLoginItem()
        }
    }

    @Published var privacyMode: Bool {
        didSet { defaults.set(privacyMode, forKey: Keys.privacyMode) }
    }

    @Published var contextAwareness: Bool {
        didSet { defaults.set(contextAwareness, forKey: Keys.contextAwareness) }
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
        // Defaults
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
        let savedKeyCode = UInt16(defaults.integer(forKey: Keys.hotkeyKeyCode))
        self.hotkeyKeyCode = savedKeyCode == 0 ? 63 : savedKeyCode
        self.hotkeyModifiers = UInt(defaults.integer(forKey: Keys.hotkeyModifiers))
        self.useHapticFeedback = defaults.object(forKey: Keys.useHapticFeedback) as? Bool ?? true
        self.playSoundEffects = defaults.object(forKey: Keys.playSoundEffects) as? Bool ?? true
        self.autoInjectText = defaults.object(forKey: Keys.autoInjectText) as? Bool ?? true
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        self.privacyMode = defaults.object(forKey: Keys.privacyMode) as? Bool ?? true // ON by default
        self.contextAwareness = defaults.object(forKey: Keys.contextAwareness) as? Bool ?? true
        self.smartFormatting = defaults.object(forKey: Keys.smartFormatting) as? Bool ?? true
        self.autoAddToDictionary = defaults.object(forKey: Keys.autoAddToDictionary) as? Bool ?? true
        self.translationEnabled = defaults.bool(forKey: Keys.translationEnabled)
        self.targetLanguage = defaults.string(forKey: Keys.targetLanguage) ?? "en"

        // Load dictionary
        if let data = defaults.data(forKey: Keys.dictionaryEntries),
           let entries = try? JSONDecoder().decode([DictionaryEntry].self, from: data) {
            self.dictionaryEntries = entries
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

    // MARK: - Style Persistence

    private func saveStyleProfiles() {
        if let data = try? JSONEncoder().encode(styleProfiles) {
            defaults.set(data, forKey: Keys.styleProfiles)
        }
    }

    // MARK: - Launch at Login

    private func updateLoginItem() {
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update login item: \(error)")
            }
        }
    }

    // MARK: - API Key Management (Keychain)

    var openAIAPIKey: String? {
        get { readKeychain(account: "openai_api_key") ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"] }
        set {
            if let value = newValue {
                saveKeychain(account: "openai_api_key", value: value)
            } else {
                deleteKeychain(account: "openai_api_key")
            }
            objectWillChange.send()
        }
    }

    var claudeAPIKey: String? {
        get { readKeychain(account: "claude_api_key") ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] }
        set {
            if let value = newValue {
                saveKeychain(account: "claude_api_key", value: value)
            } else {
                deleteKeychain(account: "claude_api_key")
            }
            objectWillChange.send()
        }
    }

    var hasAPIKeys: Bool {
        openAIAPIKey != nil && claudeAPIKey != nil &&
        !(openAIAPIKey?.isEmpty ?? true) && !(claudeAPIKey?.isEmpty ?? true)
    }

    // MARK: - Keychain Helpers

    private func saveKeychain(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        deleteKeychain(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func readKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
