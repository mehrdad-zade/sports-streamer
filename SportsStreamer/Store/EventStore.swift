import Foundation
import Observation

@MainActor
@Observable
final class EventStore {
    private(set) var events: [Event] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var loadedSite: URL?

    @ObservationIgnored private var loadTask: Task<Void, Never>?

    func reload(from site: URL?) {
        loadTask?.cancel()
        loadTask = Task { await load(site) }
    }

    func load(_ site: URL?) async {
        guard let site else {
            events = []
            errorMessage = "Add a valid site URL in Settings."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let home = try await HTMLFetcher.fetch(site)
            var merged = EventListParser.parse(html: home.html, pageURL: home.finalURL)

            // Category pages (/football, /nba, …) usually list more events than the homepage.
            let categories = EventListParser.categoryLinks(html: home.html, pageURL: home.finalURL)
            let categoryEvents = await withTaskGroup(of: [Event].self) { group in
                for category in categories {
                    group.addTask {
                        guard let page = try? await HTMLFetcher.fetch(category.url, referer: site) else { return [] }
                        return EventListParser.parse(html: page.html, pageURL: page.finalURL, sport: Self.displayName(category.name))
                    }
                }
                var all: [Event] = []
                for await events in group { all += events }
                return all
            }
            var index = Dictionary(uniqueKeysWithValues: merged.enumerated().map { ($1.url, $0) })
            for event in categoryEvents {
                if let i = index[event.url] {
                    if merged[i].sport == nil { merged[i].sport = event.sport }
                } else {
                    index[event.url] = merged.count
                    merged.append(event)
                }
            }

            guard !Task.isCancelled else { return }
            events = merged.filter { !$0.hasEnded }.sorted(by: Self.order)
            loadedSite = site
            if events.isEmpty { errorMessage = "No events found on \(site.host ?? site.absoluteString)." }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Couldn't load \(site.host ?? "site"): \(error.localizedDescription)"
        }
    }

    nonisolated private static func displayName(_ raw: String) -> String {
        raw == raw.uppercased() && raw.count > 3 ? raw.capitalized : raw
    }

    private static func order(_ a: Event, _ b: Event) -> Bool {
        if a.isLive != b.isLive { return a.isLive }
        switch (a.start, b.start) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.title < b.title
        }
    }
}
