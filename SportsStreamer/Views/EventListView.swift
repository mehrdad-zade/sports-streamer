import SwiftUI

struct EventListView: View {
    let query: String
    @Environment(AppSettings.self) private var settings
    @Environment(EventStore.self) private var store

    private var filtered: [Event] { store.events.filter { $0.matches(query) } }

    var body: some View {
        let events = filtered
        let live = events.filter(\.isLive)
        let upcoming = events.filter { !$0.isLive }

        List {
            if let error = store.errorMessage, !store.isLoading {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            if !live.isEmpty {
                Section("Live now") { ForEach(live) { row($0) } }
            }
            if !upcoming.isEmpty {
                Section("Upcoming") { ForEach(upcoming) { row($0) } }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if store.isLoading && store.events.isEmpty {
                ProgressView("Finding events…")
            } else if events.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
            } else if events.isEmpty && store.errorMessage == nil && !store.isLoading {
                ContentUnavailableView("No events", systemImage: "sportscourt", description: Text("Pull to refresh."))
            }
        }
        .refreshable { await store.load(settings.resolvedSiteURL) }
    }

    private func row(_ event: Event) -> some View {
        NavigationLink(value: event) { EventRow(event: event) }
    }
}

struct EventRow: View {
    let event: Event

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.body.weight(.semibold)).lineLimit(2)
                HStack(spacing: 6) {
                    if let sport = event.sport { Text(sport) }
                    if let subtitle = event.subtitle { Text(subtitle) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            if event.isLive {
                Text("LIVE")
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.red, in: Capsule())
                    .foregroundStyle(.white)
            } else if let start = event.start {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(start, style: .time).font(.subheadline.monospacedDigit())
                    Text(start, format: .dateTime.weekday(.abbreviated).day()).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
