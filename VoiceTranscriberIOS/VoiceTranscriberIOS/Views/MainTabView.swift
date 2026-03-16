import SwiftUI

struct MainTabView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            HomeView(appState: appState)
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(AppTab.home)

            TranscriptHistoryView(appState: appState)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(AppTab.history)

            StatsView(appState: appState)
                .tabItem {
                    Label("Stats", systemImage: "chart.bar")
                }
                .tag(AppTab.stats)

            DictionaryView(config: appState.config)
                .tabItem {
                    Label("Dictionary", systemImage: "character.book.closed")
                }
                .tag(AppTab.dictionary)

            SettingsView(appState: appState)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(AppTab.settings)
        }
        .tint(.blue)
    }
}
