import SwiftUI

struct OnboardingView: View {
    @ObservedObject var config: SharedConfig
    let onComplete: () -> Void

    @State private var currentStep = 0
    @State private var openAIKey = ""
    @State private var claudeKey = ""
    @State private var micPermissionGranted = false

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { step in
                    Capsule()
                        .fill(step <= currentStep ? Color.blue : Color(.tertiarySystemFill))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            TabView(selection: $currentStep) {
                // Step 1: Welcome
                welcomeStep.tag(0)

                // Step 2: Microphone
                microphoneStep.tag(1)

                // Step 3: API Keys
                apiKeysStep.tag(2)

                // Step 4: Keyboard Setup
                keyboardStep.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentStep)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Welcome Step

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text("Welcome to Verbalize")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Voice-to-text that learns from you. Transcribe speech anywhere on your iPhone with the Verbalize keyboard.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "mic.fill", color: .blue, text: "Tap mic on keyboard to transcribe")
                FeatureRow(icon: "brain.head.profile", color: .purple, text: "Self-learning from your corrections")
                FeatureRow(icon: "globe", color: .green, text: "Translation to 20+ languages")
                FeatureRow(icon: "character.book.closed", color: .orange, text: "Custom dictionary for names & terms")
            }
            .padding(.horizontal, 32)

            Spacer()

            Button {
                withAnimation { currentStep = 1 }
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Microphone Step

    private var microphoneStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: micPermissionGranted ? "mic.circle.fill" : "mic.slash.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(micPermissionGranted ? .green : .orange)

            Text("Microphone Access")
                .font(.title)
                .fontWeight(.bold)

            Text("Verbalize needs microphone access to record your voice for transcription.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if micPermissionGranted {
                Label("Permission Granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.headline)
            } else {
                Button("Grant Microphone Access") {
                    Task {
                        micPermissionGranted = await AudioRecorderIOS.requestMicrophonePermission()
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()

            Button {
                withAnimation { currentStep = 2 }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .onAppear {
            micPermissionGranted = AudioRecorderIOS.microphonePermissionGranted
        }
    }

    // MARK: - API Keys Step

    private var apiKeysStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "key.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                    .padding(.top, 40)

                Text("API Keys")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Verbalize uses OpenAI Whisper for transcription and Claude for intelligent text cleanup.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OpenAI API Key")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SecureField("sk-...", text: $openAIKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Claude API Key")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SecureField("sk-ant-...", text: $claudeKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                }
                .padding(.horizontal, 24)

                if config.hasAPIKeys {
                    Label("Keys configured", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }

                Spacer(minLength: 40)

                Button {
                    if !openAIKey.isEmpty { config.openAIAPIKey = openAIKey }
                    if !claudeKey.isEmpty { config.claudeAPIKey = claudeKey }
                    withAnimation { currentStep = 3 }
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            openAIKey = config.openAIAPIKey ?? ""
            claudeKey = config.claudeAPIKey ?? ""
        }
    }

    // MARK: - Keyboard Setup Step

    private var keyboardStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text("Install Keyboard")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 16) {
                SetupStepRow(number: 1, text: "Open Settings")
                SetupStepRow(number: 2, text: "Go to General > Keyboard > Keyboards")
                SetupStepRow(number: 3, text: "Tap \"Add New Keyboard...\"")
                SetupStepRow(number: 4, text: "Select \"Verbalize\"")
                SetupStepRow(number: 5, text: "Tap Verbalize > Enable \"Allow Full Access\"")
            }
            .padding(.horizontal, 32)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open Settings", systemImage: "gear")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                config.hasCompletedOnboarding = true
                onComplete()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Helper Views

struct FeatureRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

struct SetupStepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.blue)
                .clipShape(Circle())

            Text(text)
                .font(.subheadline)
        }
    }
}
