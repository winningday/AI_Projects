import Foundation
import Security

/// Manages application configuration including API keys (stored in Keychain) and user preferences.
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

    // MARK: - Init

    private init() {
        // Default hotkey: Fn key (keyCode 63) with no modifiers
        self.hotkeyKeyCode = UInt16(defaults.integer(forKey: Keys.hotkeyKeyCode))
        if self.hotkeyKeyCode == 0 {
            self.hotkeyKeyCode = 63 // Fn key
        }
        self.hotkeyModifiers = UInt(defaults.integer(forKey: Keys.hotkeyModifiers))

        self.useHapticFeedback = defaults.object(forKey: Keys.useHapticFeedback) as? Bool ?? true
        self.playSoundEffects = defaults.object(forKey: Keys.playSoundEffects) as? Bool ?? true
        self.autoInjectText = defaults.object(forKey: Keys.autoInjectText) as? Bool ?? true
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
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
