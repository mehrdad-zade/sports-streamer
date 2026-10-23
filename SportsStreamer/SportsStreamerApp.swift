import AVFoundation
import SwiftUI

@main
struct SportsStreamerApp: App {
    @State private var settings = AppSettings()
    @State private var store = EventStore()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        Task { @MainActor in _ = await AdBlocker.ruleList() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(store)
        }
    }
}
