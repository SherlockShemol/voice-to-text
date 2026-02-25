import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case home = "首页"
    case history = "历史记录"
    case hotwords = "词典"
    case settings = "设置"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house"
        case .history: return "clock"
        case .hotwords: return "text.book.closed"
        case .settings: return "gear"
        }
    }
}

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var historyStore: TranscriptionHistoryStore
    @EnvironmentObject var hotwordsManager: HotwordsManager
    @State private var selectedItem: SidebarItem = .home

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(SidebarItem.allCases, selection: $selectedItem) { item in
            Label(item.rawValue, systemImage: item.icon)
                .tag(item)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 240)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selectedItem {
        case .home:
            HomeView()
                .environmentObject(appState)
        case .history:
            HistoryView()
                .environmentObject(historyStore)
        case .hotwords:
            HotwordsView()
                .environmentObject(hotwordsManager)
        case .settings:
            SettingsView()
                .environmentObject(appState)
                .environmentObject(historyStore)
        }
    }
}
