import SwiftUI
import AVFoundation

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
    @State private var micGranted = false
    @State private var axGranted = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            permissionsTab
                .tabItem { Label("Permissions", systemImage: "lock.shield") }

            apiKeysTab
                .tabItem { Label("API Keys", systemImage: "key") }

            hotkeyTab
                .tabItem { Label("Hotkey", systemImage: "keyboard") }
        }
        .frame(width: 520, height: 400)
        .onAppear {
            openAIKey = config.openAIAPIKey ?? ""
            claudeKey = config.claudeAPIKey ?? ""
            refreshPermissions()
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Haptic feedback on recording start/stop", isOn: $config.useHapticFeedback)
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
                LabeledContent("Storage") {
                    Button("Show in Finder") {
                        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                        let appDir = appSupport.appendingPathComponent("Verbalize")
                        NSWorkspace.shared.open(appDir)
                    }
                    .controlSize(.small)
                }
            } header: {
                Text("Data")
            }

            Section {
                LabeledContent("Version") {
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Permissions Tab

    private var permissionsTab: some View {
        Form {
            Section {
                PermissionRow(
                    icon: "mic.fill",
                    color: .red,
                    title: "Microphone",
                    description: "Record speech for transcription",
                    isGranted: micGranted,
                    action: {
                        AVCaptureDevice.requestAccess(for: .audio) { granted in
                            DispatchQueue.main.async {
                                micGranted = granted
                                if !granted {
                                    openSystemPrefs("Privacy_Microphone")
                                }
                            }
                        }
                    },
                    openSettings: { openSystemPrefs("Privacy_Microphone") }
                )

                PermissionRow(
                    icon: "hand.raised.fill",
                    color: .blue,
                    title: "Accessibility",
                    description: "Global hotkey & text injection",
                    isGranted: axGranted,
                    action: {
                        let _ = hotkeyManager.checkAccessibilityPermission()
                        openSystemPrefs("Privacy_Accessibility")
                    },
                    openSettings: { openSystemPrefs("Privacy_Accessibility") }
                )
            } header: {
                Text("Required Permissions")
            }

            Section {
                Button("Refresh Status") { refreshPermissions() }
                    .controlSize(.small)

                Text("After granting permissions in System Settings, click Refresh or restart the app.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - API Keys Tab

    private var apiKeysTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        if showOpenAIKey {
                            TextField("Paste full key: sk-proj-...", text: $openAIKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("Paste full key: sk-proj-...", text: $openAIKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button(action: { showOpenAIKey.toggle() }) {
                            Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                    Link("Get your key at platform.openai.com",
                         destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.caption)
                }
            } header: {
                HStack {
                    Text("OpenAI API Key")
                    Spacer()
                    if !(config.openAIAPIKey ?? "").isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        if showClaudeKey {
                            TextField("Paste full key: sk-ant-api03-...", text: $claudeKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("Paste full key: sk-ant-api03-...", text: $claudeKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button(action: { showClaudeKey.toggle() }) {
                            Image(systemName: showClaudeKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                    Link("Get your key at console.anthropic.com",
                         destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                        .font(.caption)
                }
            } header: {
                HStack {
                    Text("Anthropic Claude API Key")
                    Spacer()
                    if !(config.claudeAPIKey ?? "").isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
            }

            Section {
                HStack {
                    Button("Save API Keys") {
                        config.openAIAPIKey = openAIKey.isEmpty ? nil : openAIKey
                        config.claudeAPIKey = claudeKey.isEmpty ? nil : claudeKey
                        showSavedAlert = true
                    }
                    .buttonStyle(.borderedProminent)

                    if config.hasAPIKeys {
                        Label("Saved in Keychain", systemImage: "lock.shield.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("Both keys required", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
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
                        .font(.system(size: 13))

                    Text(HotKeyManager.keyName(for: config.hotkeyKeyCode, modifiers: config.hotkeyModifiers))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
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
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Press any key combination...")
                            .foregroundColor(.orange)
                            .font(.system(size: 13))
                    }
                    Button("Cancel") {
                        isCapturingHotkey = false
                        hotkeyManager.stopCapturingHotkey()
                    }
                    .controlSize(.small)
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
                VStack(alignment: .leading, spacing: 8) {
                    TipRow(icon: "hand.tap", text: "Hold the hotkey to record, release to stop and process")
                    TipRow(icon: "fn", text: "Fn key is great as push-to-talk since it rarely conflicts")
                    TipRow(icon: "option", text: "Try modifier combos like \u{2325}Space or \u{2303}\u{21e7}R")
                }
            } header: {
                Text("Tips")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Helpers

    private func refreshPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        axGranted = AXIsProcessTrusted()
    }

    private func openSystemPrefs(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Permission Row

private struct PermissionRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : icon)
                .font(.system(size: 18))
                .foregroundColor(isGranted ? .green : color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isGranted {
                Text("Granted")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.green)
            } else {
                Button("Grant", action: action)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Tip Row

private struct TipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}
