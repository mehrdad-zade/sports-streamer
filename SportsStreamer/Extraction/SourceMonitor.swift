import Foundation
import Observation

/// Parses an event's sources and keeps re-checking which ones are actually streaming.
@MainActor
@Observable
final class SourceMonitor {
    private(set) var sources: [StreamSource] = []
    private(set) var isLoadingSources = false
    private(set) var completedPasses = 0
    var loadError: String?

    @ObservationIgnored var onSourceAlive: ((StreamSource) -> Void)?
    @ObservationIgnored var onPassFinished: (() -> Void)?

    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var inFlight = Set<Int>()
    @ObservationIgnored private var eventURL: URL?

    private static let maxConcurrentChecks = 3

    var checkedCount: Int { sources.filter { $0.lastChecked != nil }.count }

    func start(event: Event, interval: @escaping @MainActor () -> Int) {
        stop()
        eventURL = event.url
        sources = []
        completedPasses = 0
        loopTask = Task { [weak self] in
            await self?.loadSources(for: event)
            while let self, !Task.isCancelled {
                await self.checkAll()
                self.completedPasses += 1
                self.onPassFinished?()
                try? await Task.sleep(for: .seconds(max(15, interval())))
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        inFlight.removeAll()
    }

    func recheckNow() {
        Task { await checkAll() }
    }

    func markDead(_ id: Int) {
        guard let i = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[i].status = .dead
        sources[i].lastChecked = Date()
    }

    private func loadSources(for event: Event) async {
        isLoadingSources = true
        defer { isLoadingSources = false }
        do {
            let page = try await HTMLFetcher.fetch(event.url)
            guard !Task.isCancelled else { return }
            sources = SourceParser.parse(html: page.html, pageURL: page.finalURL)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
            sources = [StreamSource(id: 0, pageURL: event.url, embedURL: event.url, label: "Event page")]
        }
    }

    private func checkAll() async {
        let ids = sources.map(\.id)
        await withTaskGroup(of: Void.self) { group in
            var pending = ids.makeIterator()
            for _ in 0..<Self.maxConcurrentChecks {
                if let id = pending.next() { group.addTask { await self.check(id) } }
            }
            while await group.next() != nil {
                if let id = pending.next() { group.addTask { await self.check(id) } }
            }
        }
    }

    private func check(_ id: Int) async {
        guard !Task.isCancelled, let source = sources.first(where: { $0.id == id }),
              inFlight.insert(id).inserted else { return }
        defer { inFlight.remove(id) }

        // Cheap path: a known-good manifest that still answers is still alive.
        if let stream = source.resolved, await HTMLFetcher.isPlayableManifest(stream) {
            update(source) { $0.lastChecked = Date() }
            return
        }

        if !source.isAlive { update(source) { $0.status = .checking } }
        var result = await StreamSniffer.sniff(page: source.pageURL, referer: eventURL)
        if result == nil, source.embedURL != source.pageURL, !Task.isCancelled {
            result = await StreamSniffer.sniff(page: source.embedURL, referer: source.pageURL)
        }
        guard !Task.isCancelled else {
            update(source) { if $0.status == .checking { $0.status = .unknown } }
            return
        }
        update(source) {
            $0.status = result.map { .alive($0) } ?? .dead
            $0.lastChecked = Date()
        }
        if result != nil, let fresh = sources.first(where: { $0.id == id }) {
            onSourceAlive?(fresh)
        }
    }

    private func update(_ source: StreamSource, _ change: (inout StreamSource) -> Void) {
        // Ignore results for a source list that has since been replaced.
        guard let i = sources.firstIndex(where: { $0.id == source.id && $0.pageURL == source.pageURL }) else { return }
        change(&sources[i])
    }
}
