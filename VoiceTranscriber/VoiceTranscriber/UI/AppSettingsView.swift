import SwiftUI
import AVFoundation

/// In-app settings view (shown in the main window sidebar).
struct AppSettingsView: View {
    @ObservedObject var config: ConfigManager
    @ObservedObject var hotkeyManager: HotKeyManager
    @ObservedObject var database: TranscriptDatabase

    @State private var openAIKey = ""
    @State private var claudeKey = ""
    @State private var showOpenAIKey = false
    @State private var showClaudeKey = false
    @State private var isCapturingHotkey = false
    @State private var showSavedAlert = false
    @State private var showDeleteConfirm = false
    @State private var micGranted = false
    @State private var axGranted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.system(size: 26, weight: .bold))

                // General section
                SettingsSection(title: "General", icon: "gear") {
                    Toggle("Launch at login", isOn: $config.launchAtLogin)
                    Toggle("Haptic feedback", isOn: $config.useHapticFeedback)
                    Toggle("Sound effects", isOn: $config.playSoundEffects)
                    Toggle("Auto-inject text into active field", isOn: $config.autoInjectText)
                }

                // Hotkey section
                SettingsSection(title: "Hotkey", icon: "keyboard") {
                    HStack {
                        Text("Current hotkey:")
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
                            ProgressView().controlSize(.small)
                            Text("Press any key combination...")
                                .foregroundColor(.orange)
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
                }

                // Extras section
                SettingsSection(title: "Extras", icon: "sparkles") {
                    Toggle("Smart formatting (code, technical terms)", isOn: $config.smartFormatting)
                    Toggle("Auto-add corrected words to dictionary", isOn: $config.autoAddToDictionary)
                    Toggle("Context awareness (read surrounding text for accuracy)", isOn: $config.contextAwareness)

                    Text("Context awareness reads a small amount of text from the active field to help spell names correctly and understand topic context.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }

                // Permissions section
                SettingsSection(title: "Permissions", icon: "lock.shield") {
                    PermissionItem(
                        icon: "mic.fill", color: .red,
                        title: "Microphone", description: "Record speech",
                        isGranted: micGranted,
                        action: {
                            AVCaptureDevice.requestAccess(for: .audio) { granted in
                                DispatchQueue.main.async { micGranted = granted }
                            }
                        }
                    )
                    PermissionItem(
                        icon: "hand.raised.fill", color: .blue,
                        title: "Accessibility", description: "Global hotkey & text injection",
                        isGranted: axGranted,
                        action: {
                            let _ = hotkeyManager.checkAccessibilityPermission()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    )

                    Button("Refresh Permissions") { refreshPermissions() }
                        .controlSize(.small)
                }

                // API Keys section
                SettingsSection(title: "API Keys", icon: "key") {
                    APIKeyField(
                        label: "OpenAI",
                        placeholder: "sk-proj-...",
                        key: $openAIKey,
                        showKey: $showOpenAIKey,
                        isSaved: !(config.openAIAPIKey ?? "").isEmpty,
                        link: ("platform.openai.com", "https://platform.openai.com/api-keys")
                    )
                    APIKeyField(
                        label: "Anthropic Claude",
                        placeholder: "sk-ant-api03-...",
                        key: $claudeKey,
                        showKey: $showClaudeKey,
                        isSaved: !(config.claudeAPIKey ?? "").isEmpty,
                        link: ("console.anthropic.com", "https://console.anthropic.com/settings/keys")
                    )

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
                        }
                    }
                }

                // Data & Privacy section
                SettingsSection(title: "Data & Privacy", icon: "hand.raised") {
                    Toggle(isOn: $config.privacyMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Privacy mode")
                            Text("Do not use transcription data for model training")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    LabeledContent("Transcripts stored") {
                        Text("\(database.transcripts.count) entries")
                            .foregroundColor(.secondary)
                    }

                    LabeledContent("Storage location") {
                        Button("Show in Finder") {
                            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                            let appDir = appSupport.appendingPathComponent("VoiceTranscriber")
                            NSWorkspace.shared.open(appDir)
                        }
                        .controlSize(.small)
                    }

                    Button("Delete All History & Activity", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .controlSize(.small)
                }

                // About section
                SettingsSection(title: "About", icon: "info.circle") {
                    LabeledContent("Version") {
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    LabeledContent("Whisper Model") {
                        Text("gpt-4o-mini-transcribe")
                            .foregroundColor(.secondary)
                    }
                    LabeledContent("Cleanup Model") {
                        Text("Claude Haiku 4.5")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            openAIKey = config.openAIAPIKey ?? ""
            claudeKey = config.claudeAPIKey ?? ""
            refreshPermissions()
        }
        .alert("API Keys Saved", isPresented: $showSavedAlert) {
            Button("OK") {}
        } message: {
            Text("Your API keys have been saved securely in the macOS Keychain.")
        }
        .alert("Delete All History?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                try? database.deleteAll()
            }
        } message: {
            Text("This will permanently delete all transcripts and activity history. This cannot be undone.")
        }
    }

    private func refreshPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        axGranted = AXIsProcessTrusted()
    }
}

// MARK: - Settings Section

private struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }
}

// MARK: - Permission Item

private struct PermissionItem: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : icon)
                .foregroundColor(isGranted ? .green : color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(description).font(.system(size: 11)).foregroundColor(.secondary)
            }

            Spacer()

            if isGranted {
                Text("Granted").font(.system(size: 11, weight: .medium)).foregroundColor(.green)
            } else {
                Button("Grant", action: action)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - API Key Field

private struct APIKeyField: View {
    let label: String
    let placeholder: String
    @Binding var key: String
    @Binding var showKey: Bool
    let isSaved: Bool
    let link: (String, String)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                if isSaved {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                }
            }

            HStack {
                if showKey {
                    TextField(placeholder, text: $key)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                } else {
                    SecureField(placeholder, text: $key)
                        .textFieldStyle(.roundedBorder)
                }
                Button(action: { showKey.toggle() }) {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
            }

            Link("Get a key at \(link.0)", destination: URL(string: link.1)!)
                .font(.system(size: 11))
        }
    }
}
