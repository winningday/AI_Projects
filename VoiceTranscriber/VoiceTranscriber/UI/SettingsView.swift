import SwiftUI

/// Settings window for configuring hotkeys, API keys, and app preferences.
struct SettingsView: View {
    @ObservedObject var config: ConfigManager
    @ObservedObject var hotkeyManager: HotKeyManager

    @State private var openAIKey: String = ""
    @State private var claudeKey: String = ""
    @State private var showOpenAIKey = false
    @State private var showClaudeKey = false
    @State private var isCapturingHotkey = false
    @State private var showSavedAlert = false

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            apiKeysTab
                .tabItem {
                    Label("API Keys", systemImage: "key")
                }

            hotkeyTab
                .tabItem {
                    Label("Hotkey", systemImage: "keyboard")
                }
        }
        .frame(width: 480, height: 320)
        .onAppear {
            openAIKey = config.openAIAPIKey ?? ""
            claudeKey = config.claudeAPIKey ?? ""
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Haptic feedback", isOn: $config.useHapticFeedback)
                Toggle("Sound effects", isOn: $config.playSoundEffects)
                Toggle("Auto-inject text into active field", isOn: $config.autoInjectText)
            } header: {
                Text("Behavior")
            }

            Section {
                LabeledContent("Transcripts") {
                    Text("\(TranscriptDatabase.shared.transcripts.count) entries")
                        .foregroundColor(.secondary)
                }

                LabeledContent("Database Location") {
                    Button("Show in Finder") {
                        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                        let appDir = appSupport.appendingPathComponent("VoiceTranscriber")
                        NSWorkspace.shared.open(appDir)
                    }
                }
            } header: {
                Text("Data")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - API Keys Tab

    private var apiKeysTab: some View {
        Form {
            Section {
                HStack {
                    if showOpenAIKey {
                        TextField("sk-...", text: $openAIKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("sk-...", text: $openAIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(action: { showOpenAIKey.toggle() }) {
                        Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                Text("Used for Whisper speech-to-text. Get your key at platform.openai.com")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("OpenAI API Key")
            }

            Section {
                HStack {
                    if showClaudeKey {
                        TextField("sk-ant-...", text: $claudeKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("sk-ant-...", text: $claudeKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(action: { showClaudeKey.toggle() }) {
                        Image(systemName: showClaudeKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                Text("Used for transcript cleanup. Get your key at console.anthropic.com")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Anthropic Claude API Key")
            }

            Section {
                Button("Save API Keys") {
                    config.openAIAPIKey = openAIKey.isEmpty ? nil : openAIKey
                    config.claudeAPIKey = claudeKey.isEmpty ? nil : claudeKey
                    showSavedAlert = true
                }
                .buttonStyle(.borderedProminent)

                if !config.hasAPIKeys {
                    Label("Both API keys are required for full functionality", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("API Keys Saved", isPresented: $showSavedAlert) {
            Button("OK") {}
        } message: {
            Text("Your API keys have been saved securely in the macOS Keychain.")
        }
    }

    // MARK: - Hotkey Tab

    private var hotkeyTab: some View {
        Form {
            Section {
                HStack {
                    Text("Current hotkey:")
                    Text(HotKeyManager.keyName(for: config.hotkeyKeyCode, modifiers: config.hotkeyModifiers))
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color(nsColor: .separatorColor))
                                )
                        )
                    Spacer()
                }

                if isCapturingHotkey {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Press any key combination...")
                            .foregroundColor(.orange)
                    }

                    Button("Cancel") {
                        isCapturingHotkey = false
                        hotkeyManager.stopCapturingHotkey()
                    }
                } else {
                    Button("Change Hotkey") {
                        isCapturingHotkey = true
                        hotkeyManager.startCapturingHotkey()
                        hotkeyManager.onHotkeyCaptured = { keyCode, modifiers in
                            hotkeyManager.updateHotkey(keyCode: keyCode, modifiers: modifiers)
                            isCapturingHotkey = false
                        }
                    }
                }
            } header: {
                Text("Global Hotkey")
            }

            Section {
                Text("Hold the hotkey to record, release to stop and process.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("The Fn key works well as a push-to-talk key since it doesn't conflict with most apps.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("You can also use modifier+key combinations like ⌥Space or ⌃⇧R.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Tips")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
