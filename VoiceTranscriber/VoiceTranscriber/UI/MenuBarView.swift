import SwiftUI

/// The menu bar extra view — primary interface for the app.
struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Status header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: statusIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(statusColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Verbalize")
                        .font(.system(size: 13, weight: .semibold))
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(statusBadge)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(statusColor.opacity(0.12))
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Error banner
            if let error = appState.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .lineLimit(2)
                    Spacer()
                    Button(action: { appState.lastError = nil }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08))

                Divider()
            }

            // Actions
            VStack(spacing: 2) {
                if appState.isRecording {
                    MenuButton(
                        icon: "stop.circle.fill",
                        label: "Cancel Recording",
                        color: .red,
                        action: { appState.cancelRecording() }
                    )
                } else if appState.isProcessing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(appState.statusMessage)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                } else {
                    MenuButton(
                        icon: "clock.arrow.circlepath",
                        label: "Transcript History",
                        action: { appState.showTranscriptHistory() }
                    )
                }
            }
            .padding(.vertical, 4)

            // Last transcript preview
            if let last = appState.lastTranscript, !appState.isRecording && !appState.isProcessing {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("LAST TRANSCRIPT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .tracking(0.5)

                    Text(last.cleanedText)
                        .font(.system(size: 12))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 12) {
                        Text(last.formattedTimestamp)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Spacer()

                        Button(action: { copyToClipboard(last.cleanedText) }) {
                            HStack(spacing: 3) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy")
                            }
                            .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            Divider()

            // Translation quick toggle
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 12))
                        .foregroundColor(appState.config.translationEnabled ? .blue : .secondary)

                    Text("Translation")
                        .font(.system(size: 13))

                    Spacer()

                    // Segmented OFF / ON toggle
                    HStack(spacing: 0) {
                        Button(action: { appState.config.translationEnabled = false }) {
                            Text("Off")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(!appState.config.translationEnabled ? .primary : .secondary)
                                .frame(width: 36, height: 20)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(!appState.config.translationEnabled ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                                        .shadow(color: !appState.config.translationEnabled ? .black.opacity(0.1) : .clear, radius: 1, y: 1)
                                )
                        }
                        .buttonStyle(.plain)

                        Button(action: { appState.config.translationEnabled = true }) {
                            Text("On")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(appState.config.translationEnabled ? .white : .secondary)
                                .frame(width: 36, height: 20)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(appState.config.translationEnabled ? Color.blue : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(2)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .separatorColor).opacity(0.3))
                    )
                }

                // Language picker (always visible so user knows the target)
                HStack(spacing: 6) {
                    Text(appState.config.translationEnabled ? "Translating to:" : "Language:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)

                    Picker("", selection: Binding(
                        get: { appState.config.targetLanguage },
                        set: { appState.config.targetLanguage = $0 }
                    )) {
                        ForEach(ConfigManager.supportedLanguages, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: 140)

                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            // Hotkey info (dynamically updates)
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("Hold")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Text(appState.hotkeyDescription)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                            )
                    )

                Text("to record")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            // Bottom buttons
            VStack(spacing: 2) {
                MenuButton(
                    icon: "macwindow",
                    label: "Open Verbalize",
                    action: { appState.showMainWindow() }
                )

                MenuButton(
                    icon: "arrow.counterclockwise",
                    label: "Run Setup Again",
                    action: { appState.showOnboardingWindow() }
                )

                Divider()
                    .padding(.horizontal, 8)

                MenuButton(
                    icon: "power",
                    label: "Quit Verbalize",
                    shortcut: "\u{2318}Q",
                    action: { NSApplication.shared.terminate(nil) }
                )
            }
            .padding(.vertical, 4)
        }
        .frame(width: 300)
        .onAppear {
            appState.appDidFinishLaunching()
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        if appState.isRecording { return .red }
        if appState.isProcessing { return .orange }
        if appState.lastError != nil { return .orange }
        return .green
    }

    private var statusIcon: String {
        if appState.isRecording { return "mic.fill" }
        if appState.isProcessing { return "arrow.triangle.2.circlepath" }
        return "mic"
    }

    private var statusText: String {
        if appState.isRecording { return "Recording audio..." }
        if appState.isProcessing { return appState.statusMessage }
        if appState.lastError != nil { return "Error occurred" }
        return "Ready to record"
    }

    private var statusBadge: String {
        if appState.isRecording { return "REC" }
        if appState.isProcessing { return "BUSY" }
        return "READY"
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Menu Button

private struct MenuButton: View {
    let icon: String
    let label: String
    var color: Color = .primary
    var shortcut: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundColor(color == .primary ? .secondary : color)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(color)
                Spacer()
                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
    }
}
