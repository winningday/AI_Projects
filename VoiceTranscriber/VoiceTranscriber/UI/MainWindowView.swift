import SwiftUI

/// Main application window with sidebar navigation.
struct MainWindowView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(spacing: 0) {
                // App logo/title
                HStack(spacing: 8) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.linearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    Text("VoiceTranscriber")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // Navigation items
                List(AppTab.allCases, selection: $appState.selectedTab) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
                .listStyle(.sidebar)

                Divider()

                // Recording status footer
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(appState.statusMessage)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 10))
                        Text("Hold")
                            .font(.system(size: 10))
                        Text(appState.hotkeyDescription)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                        Text("to record")
                            .font(.system(size: 10))
                        Spacer()
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .frame(minWidth: 180, maxWidth: 220)
        } detail: {
            // Content area
            switch appState.selectedTab {
            case .home:
                HomeView(appState: appState)
            case .dictionary:
                DictionaryView(config: appState.config)
            case .style:
                StyleView(config: appState.config)
            case .settings:
                AppSettingsView(
                    config: appState.config,
                    hotkeyManager: appState.hotkeyManager,
                    database: appState.database
                )
            }
        }
    }

    private var statusColor: Color {
        if appState.isRecording { return .red }
        if appState.isProcessing { return .orange }
        return .green
    }
}
