import SwiftUI

/// Main application window with sidebar navigation.
struct MainWindowView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(spacing: 0) {
                // App logo/title
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.linearGradient(
                                colors: [Color(red: 0.2, green: 0.15, blue: 0.55), Color(red: 0.12, green: 0.08, blue: 0.47)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 30, height: 30)
                        Image(systemName: "waveform")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Text("Verbalize")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Navigation items
                List(AppTab.allCases, selection: $appState.selectedTab) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
                .listStyle(.sidebar)

                Divider()

                // Status footer
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(appState.statusMessage)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    HStack(spacing: 4) {
                        Text("Hold")
                            .font(.system(size: 10))
                        KeyBadge(text: appState.hotkeyDescription)
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
            switch appState.selectedTab {
            case .home:
                HomeView(appState: appState)
            case .dictionary:
                DictionaryView(config: appState.config)
            case .style:
                StyleView(config: appState.config)
            case .settings:
                AppSettingsView(
                    appState: appState,
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

// MARK: - Key Badge (reusable hotkey display)

struct KeyBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                    )
            )
    }
}
