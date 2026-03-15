import SwiftUI
import AVFoundation

/// Guided setup flow that walks users through permissions and API key configuration.
struct OnboardingView: View {
    @ObservedObject var config: ConfigManager
    @ObservedObject var hotkeyManager: HotKeyManager
    var onComplete: () -> Void

    @State private var currentStep = 0
    @State private var micGranted = false
    @State private var accessibilityGranted = false
    @State private var openAIKey = ""
    @State private var claudeKey = ""
    @State private var permissionTimer: Timer?

    private let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "mic.badge.plus")
                    .font(.system(size: 44))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                Text("Welcome to Verbalize")
                    .font(.system(size: 22, weight: .bold))

                Text("Let's get you set up in a few quick steps")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            // Progress bar
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Capsule()
                        .fill(step <= currentStep ? Color.accentColor : Color(nsColor: .separatorColor))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)

            // Step content
            Group {
                switch currentStep {
                case 0: microphoneStep
                case 1: accessibilityStep
                case 2: apiKeysStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }

                Spacer()

                if currentStep < totalSteps - 1 {
                    Button(action: { withAnimation { currentStep += 1 } }) {
                        HStack {
                            Text(canSkipStep ? "Next" : "Skip for Now")
                            Image(systemName: "chevron.right")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: finishOnboarding) {
                        HStack {
                            Text("Get Started")
                            Image(systemName: "checkmark.circle")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!config.hasAPIKeys)
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 480)
        .onAppear {
            refreshPermissionStatus()
            // Poll permissions periodically so UI updates when user grants in System Settings
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
                DispatchQueue.main.async { refreshPermissionStatus() }
            }
        }
        .onDisappear {
            permissionTimer?.invalidate()
        }
    }

    // MARK: - Step 1: Microphone

    private var microphoneStep: some View {
        VStack(spacing: 20) {
            PermissionCard(
                icon: "mic.fill",
                iconColor: .red,
                title: "Microphone Access",
                description: "Verbalize needs microphone access to record your speech for transcription.",
                isGranted: micGranted,
                actionLabel: micGranted ? "Granted" : "Grant Access",
                action: requestMicrophoneAccess
            )

            if !micGranted {
                HelpText("If the prompt doesn't appear, open System Settings manually:")
                SystemSettingsButton(
                    label: "Open Microphone Settings",
                    urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                )
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Step 2: Accessibility

    private var accessibilityStep: some View {
        VStack(spacing: 20) {
            PermissionCard(
                icon: "hand.raised.fill",
                iconColor: .blue,
                title: "Accessibility Access",
                description: "Required for global hotkey listening and typing text into other apps. You'll need to add Verbalize in System Settings.",
                isGranted: accessibilityGranted,
                actionLabel: accessibilityGranted ? "Granted" : "Open Settings",
                action: openAccessibilitySettings
            )

            if !accessibilityGranted {
                VStack(alignment: .leading, spacing: 8) {
                    HelpText("Steps to enable:")
                    NumberedStep(number: 1, text: "Click \"Open Settings\" above")
                    NumberedStep(number: 2, text: "Click the + button")
                    NumberedStep(number: 3, text: "Find and add Verbalize")
                    NumberedStep(number: 4, text: "Make sure the toggle is ON")
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Step 3: API Keys

    private var apiKeysStep: some View {
        VStack(spacing: 16) {
            // OpenAI key
            VStack(alignment: .leading, spacing: 6) {
                Label("OpenAI API Key", systemImage: "key.fill")
                    .font(.headline)
                    .foregroundColor(.primary)

                TextField("Paste your full key (sk-proj-...)", text: $openAIKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                Link("Get a key at platform.openai.com",
                     destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(.caption)
            }

            // Claude key
            VStack(alignment: .leading, spacing: 6) {
                Label("Anthropic Claude API Key", systemImage: "key.fill")
                    .font(.headline)
                    .foregroundColor(.primary)

                TextField("Paste your full key (sk-ant-api03-...)", text: $claudeKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                Link("Get a key at console.anthropic.com",
                     destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.caption)
            }

            if !openAIKey.isEmpty && !claudeKey.isEmpty {
                Button(action: saveAPIKeys) {
                    Label("Save Keys to Keychain", systemImage: "lock.shield")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }

            if config.hasAPIKeys {
                Label("Keys saved securely", systemImage: "checkmark.seal.fill")
                    .foregroundColor(.green)
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Actions

    private func requestMicrophoneAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                micGranted = granted
                if !granted {
                    // Open System Settings if denied
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    private func openAccessibilitySettings() {
        // Prompt accessibility dialog
        let _ = hotkeyManager.checkAccessibilityPermission()

        // Also open the pane directly
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func saveAPIKeys() {
        config.openAIAPIKey = openAIKey.isEmpty ? nil : openAIKey
        config.claudeAPIKey = claudeKey.isEmpty ? nil : claudeKey
    }

    private func refreshPermissionStatus() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
    }

    private var canSkipStep: Bool {
        switch currentStep {
        case 0: return micGranted
        case 1: return accessibilityGranted
        case 2: return config.hasAPIKeys
        default: return true
        }
    }

    private func finishOnboarding() {
        if !openAIKey.isEmpty || !claudeKey.isEmpty {
            saveAPIKeys()
        }
        config.hasCompletedOnboarding = true
        onComplete()
    }
}

// MARK: - Reusable Components

private struct PermissionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let isGranted: Bool
    let actionLabel: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(isGranted ? Color.green.opacity(0.15) : iconColor.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: isGranted ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 24))
                    .foregroundColor(isGranted ? .green : iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                    if isGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(actionLabel, action: action)
                .buttonStyle(.bordered)
                .disabled(isGranted)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        )
    }
}

private struct HelpText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NumberedStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption2.bold())
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))

            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }
}

private struct SystemSettingsButton: View {
    let label: String
    let urlString: String

    var body: some View {
        Button(action: {
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack {
                Image(systemName: "gear")
                Text(label)
            }
        }
        .buttonStyle(.bordered)
    }
}
