import Foundation
import Observation

/// Ties together source discovery, playback, and automatic failover for one event.
@MainActor
@Observable
final class WatchSession {
    enum Mode { case native, web }

    let event: Event
    let monitor = SourceMonitor()
    let player = PlayerController()
    private(set) var currentID: Int?
    private(set) var mode: Mode = .native
    private(set) var isRunning = false
    var notice: String?

    @ObservationIgnored private let settings: AppSettings
    /// True when we fell back to the web player because nothing could be extracted.
    @ObservationIgnored private var isAutomaticWebFallback = false

    init(event: Event, settings: AppSettings) {
        self.event = event
        self.settings = settings
    }

    var currentSource: StreamSource? {
        currentID.flatMap { id in monitor.sources.first { $0.id == id } }
    }

    var aliveSources: [StreamSource] { monitor.sources.filter(\.isAlive) }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        monitor.onSourceAlive = { [weak self] in self?.sourceBecameAlive($0) }
        monitor.onPassFinished = { [weak self] in self?.passFinished() }
        player.onFailure = { [weak self] in self?.currentStreamFailed() }
        monitor.start(event: event) { [weak self] in self?.settings.recheckInterval ?? 60 }
    }

    func stop() {
        isRunning = false
        monitor.stop()
        player.stop()
    }

    /// User picked a source chip.
    func select(_ source: StreamSource) {
        isAutomaticWebFallback = false
        currentID = source.id
        notice = nil
        if let stream = source.resolved {
            mode = .native
            player.play(stream)
        } else {
            // Not (yet) extractable: show the page itself in the ad-blocked web player.
            player.stop()
            mode = .web
        }
    }

    func showInWebPlayer(_ source: StreamSource) {
        isAutomaticWebFallback = false
        currentID = source.id
        player.stop()
        mode = .web
    }

    func switchToNextAlive() {
        guard let next = nextAlive(after: currentID) else { return }
        select(next)
    }

    func nextAlive(after id: Int?) -> StreamSource? {
        let alive = aliveSources.filter { $0.id != id }
        guard let id else { return alive.first }
        return alive.first { $0.id > id } ?? alive.first
    }

    private func sourceBecameAlive(_ source: StreamSource) {
        let nothingPlaying = currentID == nil || (mode == .web && isAutomaticWebFallback)
        if nothingPlaying {
            isAutomaticWebFallback = false
            currentID = source.id
            mode = .native
            notice = nil
            player.play(source.resolved!)
        }
    }

    private func passFinished() {
        guard monitor.completedPasses == 1, currentID == nil, let first = monitor.sources.first else { return }
        notice = "Couldn't extract a direct stream. Showing the web player; sources keep being checked."
        currentID = first.id
        mode = .web
        isAutomaticWebFallback = true
    }

    private func currentStreamFailed() {
        guard let failed = currentID else { return }
        monitor.markDead(failed)
        if settings.autoSwitch, let next = nextAlive(after: failed) {
            select(next)
            notice = "Source \(failed + 1) stopped. Switched to source \(next.id + 1)."
        } else {
            currentID = nil
            notice = "Source \(failed + 1) stopped. Looking for another live source…"
            monitor.recheckNow()
        }
    }
}
