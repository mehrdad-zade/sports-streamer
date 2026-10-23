import AVFoundation
import Observation

/// Wraps AVPlayer and reports when the current stream dies (error, end of stream, or a long stall).
@MainActor
@Observable
final class PlayerController {
    let player = AVPlayer()
    private(set) var isBuffering = false
    /// Set by `NativePlayerView` while the player is presented full screen over the app.
    var isPresentingFullScreen = false

    @ObservationIgnored var onFailure: (() -> Void)?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var stallTask: Task<Void, Never>?

    private static let stallTimeout: Duration = .seconds(20)

    func play(_ stream: ResolvedStream) {
        reset()
        var options: [String: Any] = [
            "AVURLAssetHTTPHeaderFieldsKey": stream.httpHeaders,
            AVURLAssetHTTPUserAgentKey: stream.userAgent,
        ]
        if !stream.cookies.isEmpty { options[AVURLAssetHTTPCookiesKey] = stream.cookies }
        let item = AVPlayerItem(asset: AVURLAsset(url: stream.url, options: options))

        observations.append(item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in self?.fail() }
        })
        observations.append(player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            Task { @MainActor in self?.bufferingChanged(waiting) }
        })
        for name in [AVPlayerItem.failedToPlayToEndTimeNotification, AVPlayerItem.didPlayToEndTimeNotification] {
            notificationTokens.append(NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.fail() }
            })
        }

        player.replaceCurrentItem(with: item)
        player.play()
    }

    func stop() {
        reset()
    }

    private func bufferingChanged(_ waiting: Bool) {
        isBuffering = waiting
        stallTask?.cancel()
        guard waiting, player.currentItem != nil else { return }
        stallTask = Task { [weak self] in
            try? await Task.sleep(for: Self.stallTimeout)
            guard !Task.isCancelled else { return }
            self?.fail()
        }
    }

    private func fail() {
        guard player.currentItem != nil else { return }
        reset()
        onFailure?()
    }

    private func reset() {
        stallTask?.cancel()
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        notificationTokens.removeAll()
        player.replaceCurrentItem(with: nil)
        isBuffering = false
    }
}
