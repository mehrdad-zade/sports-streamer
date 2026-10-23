import SwiftUI

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(EventStore.self) private var store
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var path: [Event] = []
    @State private var query = ""
    @State private var showSettings = false
    @FocusState private var searchFocused: Bool

    private var isWatchingInLandscape: Bool { !path.isEmpty && verticalSizeClass == .compact }

    var body: some View {
        NavigationStack(path: $path) {
            EventListView(query: query)
                .navigationTitle("Live Sports")
                .navigationDestination(for: Event.self) { WatchView(event: $0) }
        }
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isWatchingInLandscape { bottomBar }
        }
        .sheet(isPresented: $showSettings, onDismiss: reloadIfSiteChanged) {
            SettingsView()
        }
        .task {
            if store.events.isEmpty { store.reload(from: settings.resolvedSiteURL) }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            BarButton(systemImage: "house.fill", label: "Home", action: goHome)
            BarButton(systemImage: "gearshape.fill", label: "Settings") { showSettings = true }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search teams, e.g. real", text: $query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { if !path.isEmpty { path.removeAll() } }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Color(.secondarySystemBackground), in: Capsule())
        }
        .padding(.horizontal)
        .padding(.top, 8)
        // Never negative: the bar must reserve its full height, or the keyboard covers part of it.
        // Without the keyboard the home-indicator safe area already provides the bottom spacing.
        .padding(.bottom, searchFocused ? 8 : 0)
        .background(.bar)
    }

    private func goHome() {
        path.removeAll()
        query = ""
        searchFocused = false
        store.reload(from: settings.resolvedSiteURL)
    }

    private func reloadIfSiteChanged() {
        if settings.resolvedSiteURL != store.loadedSite {
            path.removeAll()
            store.reload(from: settings.resolvedSiteURL)
        }
    }
}

private struct BarButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(Color(.secondarySystemBackground), in: Circle())
        }
        .accessibilityLabel(label)
    }
}
