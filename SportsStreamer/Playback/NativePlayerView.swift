import AVKit
import SwiftUI

struct NativePlayerView: UIViewControllerRepresentable {
    let controller: PlayerController
    /// Follows device orientation: entering landscape goes full screen, returning to portrait leaves it.
    var wantsFullScreen = false

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let viewController = AVPlayerViewController()
        viewController.player = controller.player
        viewController.delegate = context.coordinator
        viewController.allowsPictureInPicturePlayback = true
        viewController.canStartPictureInPictureAutomaticallyFromInline = true
        viewController.videoGravity = .resizeAspect
        context.coordinator.startObservingOrientation(of: viewController)
        return viewController
    }

    func updateUIViewController(_ viewController: AVPlayerViewController, context: Context) {
        context.coordinator.controller = controller
        if viewController.player !== controller.player { viewController.player = controller.player }
        context.coordinator.layoutOrientationChanged(toLandscape: wantsFullScreen)
    }

    static func dismantleUIViewController(_ viewController: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.stopObservingOrientation()
        // Removed while full screen (e.g. switched to the web player): don't leave the flag stuck on.
        coordinator.controller.isPresentingFullScreen = false
    }

    /// Tracks full-screen presentation so the watch screen doesn't tear down playback when it's covered by it.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency AVPlayerViewControllerDelegate {
        var controller: PlayerController
        private var lastWantsFullScreen = false
        private var lastLayoutLandscape = false
        private weak var viewController: AVPlayerViewController?
        private var orientationToken: NSObjectProtocol?

        init(controller: PlayerController) { self.controller = controller }

        /// While full screen covers the watch screen, SwiftUI stops passing it size-class changes,
        /// so rotating back to portrait has to be picked up from the device itself.
        func startObservingOrientation(of viewController: AVPlayerViewController) {
            self.viewController = viewController
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            orientationToken = NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    let orientation = UIDevice.current.orientation
                    // Ignore face up/down and unknown, which say nothing about how the phone is held.
                    guard orientation.isPortrait || orientation.isLandscape else { return }
                    self?.orientationChanged(toLandscape: orientation.isLandscape)
                }
            }
        }

        func stopObservingOrientation() {
            guard let orientationToken else { return }
            NotificationCenter.default.removeObserver(orientationToken)
            self.orientationToken = nil
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }

        /// SwiftUI's size class goes stale while full screen covers the view, and redraws keep
        /// re-sending it; only a real change counts, or it would undo the device's portrait report.
        func layoutOrientationChanged(toLandscape landscape: Bool) {
            guard landscape != lastLayoutLandscape else { return }
            lastLayoutLandscape = landscape
            orientationChanged(toLandscape: landscape)
        }

        /// Both the device and SwiftUI report rotations; act once per change, so tapping Done
        /// in landscape isn't immediately undone.
        func orientationChanged(toLandscape landscape: Bool) {
            guard landscape != lastWantsFullScreen else { return }
            lastWantsFullScreen = landscape
            // Defer so a freshly created player is in the window before presenting.
            DispatchQueue.main.async { [weak self] in
                guard let self, let viewController = self.viewController else { return }
                self.setFullScreen(landscape, on: viewController)
            }
        }

        /// AVKit has no public API for this; the selectors have been stable since iOS 11.
        /// If they ever go away, rotation simply falls back to the inline landscape layout.
        func setFullScreen(_ fullScreen: Bool, on viewController: AVPlayerViewController) {
            guard fullScreen != controller.isPresentingFullScreen,
                  !fullScreen || viewController.viewIfLoaded?.window != nil else { return }
            let selector = NSSelectorFromString(fullScreen ? "enterFullScreenAnimated:completionHandler:"
                                                           : "exitFullScreenAnimated:completionHandler:")
            guard viewController.responds(to: selector) else { return }
            typealias Method = @convention(c) (AnyObject, Selector, Bool, (@convention(block) (Bool) -> Void)?) -> Void
            let method = unsafeBitCast(viewController.method(for: selector), to: Method.self)
            method(viewController, selector, true, nil)
        }

        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            controller.isPresentingFullScreen = true
        }

        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            // AVKit pauses during the exit transition; keep a stream that was playing going.
            let player = playerViewController.player
            let wasPlaying = (player?.rate ?? 0) > 0 || player?.timeControlStatus == .waitingToPlayAtSpecifiedRate
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                guard !context.isCancelled else { return }
                self?.controller.isPresentingFullScreen = false
                if wasPlaying { player?.play() }
            }
        }
    }
}
