import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        NavigationView {
            Form {
                // MARK: - API Keys
                Section {
                    APIKeyField(
                        label: "OpenAI API Key",
                        key: Binding(
                            get: { appState.config.openAIAPIKey ?? "" },
                            set: { appState.config.openAIAPIKey = $0.isEmpty ? nil : $0 }
                        ),
                        placeholder: "sk-..."
                    )

                    APIKeyField(
                        label: "Claude API Key",
                        key: Binding(
                            get: { appState.config.claudeAPIKey ?? "" },
                            set: { appState.config.claudeAPIKey = $0.isEmpty ? nil : $0 }
                        ),
                        placeholder: "sk-ant-..."
                    )

                    if appState.config.hasAPIKeys {
                        Label("API keys configured", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                } header: {
                    Text("API Keys")
                } footer: {
                    Text("API keys are stored locally and shared with the keyboard extension via App Group.")
                }

                // MARK: - Translation
                Section {
                    Toggle("Translation", isOn: $appState.config.translationEnabled)

                    if appState.config.translationEnabled {
                        Picker("Target Language", selection: $appState.config.targetLanguage) {
                            ForEach(SharedConfig.supportedLanguages, id: \.code) { lang in
                                Text(lang.name).tag(lang.code)
                            }
                        }
                    }
                } header: {
                    Text("Translation")
                } footer: {
                    Text("When enabled, speech in any language is translated to your target language.")
                }

                // MARK: - Style
                Section {
                    Picker("Default Style", selection: $appState.config.defaultStyleTone) {
                        ForEach(StyleTone.allCases) { tone in
                            VStack(alignment: .leading) {
                                Text(tone.displayName)
                                Text(tone.subtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(tone)
                        }
                    }

                    NavigationLink("Context Styles") {
                        StyleProfilesView(config: appState.config)
                    }
                } header: {
                    Text("Style")
                } footer: {
                    Text("Controls capitalization and punctuation in transcribed text.")
                }

                // MARK: - Features
                Section("Features") {
                    Toggle("Smart Formatting", isOn: $appState.config.smartFormatting)
                    Toggle("Auto-Add to Dictionary", isOn: $appState.config.autoAddToDictionary)
                    Toggle("Sound Effects", isOn: $appState.config.playSoundEffects)
                    Toggle("Privacy Mode", isOn: $appState.config.privacyMode)
                }

                // MARK: - Typing Speed
                Section {
                    Stepper("Typing Speed: \(appState.config.typingSpeed) WPM", value: $appState.config.typingSpeed, in: 10...200, step: 5)
                } header: {
                    Text("Productivity")
                } footer: {
                    Text("Your estimated typing speed, used to calculate time saved by voice transcription.")
                }

                // MARK: - Keyboard Setup
                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Label("Set Up Keyboard", systemImage: "keyboard")
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Keyboard")
                } footer: {
                    Text("Go to Settings > General > Keyboard > Keyboards > Add New Keyboard > Verbalize. Make sure to enable \"Allow Full Access\" for voice transcription to work.")
                }

                // MARK: - Learning Data
                Section {
                    HStack {
                        Text("Dictionary Words")
                        Spacer()
                        Text("\(appState.config.dictionaryEntries.count)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Learned Corrections")
                        Spacer()
                        Text("\(appState.config.corrections.count)")
                            .foregroundColor(.secondary)
                    }

                    Button("Clear All Corrections", role: .destructive) {
                        appState.config.clearCorrections()
                    }
                } header: {
                    Text("Learning Data")
                }

                // MARK: - Data
                Section {
                    HStack {
                        Text("Total Transcriptions")
                        Spacer()
                        Text("\(appState.database.transcripts.count)")
                            .foregroundColor(.secondary)
                    }

                    Button("Delete All Transcriptions", role: .destructive) {
                        try? appState.database.deleteAll()
                    }
                } header: {
                    Text("Data")
                }

                // MARK: - About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - API Key Field

struct APIKeyField: View {
    let label: String
    @Binding var key: String
    let placeholder: String

    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                if isVisible {
                    TextField(placeholder, text: $key)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } else {
                    SecureField(placeholder, text: $key)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Style Profiles View

struct StyleProfilesView: View {
    @ObservedObject var config: SharedConfig

    var body: some View {
        Form {
            ForEach(StyleContext.allCases) { context in
                Section {
                    Picker(context.displayName, selection: Binding(
                        get: { config.styleTone(for: context) },
                        set: { config.setStyleTone($0, for: context) }
                    )) {
                        ForEach(StyleTone.allCases) { tone in
                            VStack(alignment: .leading) {
                                Text(tone.displayName)
                                Text(tone.example)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(tone)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text(context.displayName)
                } footer: {
                    Text(context.description)
                }
            }
        }
        .navigationTitle("Context Styles")
    }
}
