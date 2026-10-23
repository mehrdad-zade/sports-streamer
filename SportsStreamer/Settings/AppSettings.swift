import Foundation
import Observation

@Observable
final class AppSettings {
    static let defaultSiteURL = "https://footy4u.st/"

    var siteURL: String {
        didSet { UserDefaults.standard.set(siteURL, forKey: Keys.siteURL) }
    }

    /// Seconds between re-checks of the other sources while a stream is playing.
    var recheckInterval: Int {
        didSet { UserDefaults.standard.set(recheckInterval, forKey: Keys.recheckInterval) }
    }

    /// Automatically jump to another live source when the current one fails.
    var autoSwitch: Bool {
        didSet { UserDefaults.standard.set(autoSwitch, forKey: Keys.autoSwitch) }
    }

    var resolvedSiteURL: URL? { AppSettings.normalize(siteURL) }

    init() {
        let defaults = UserDefaults.standard
        siteURL = defaults.string(forKey: Keys.siteURL) ?? AppSettings.defaultSiteURL
        recheckInterval = defaults.object(forKey: Keys.recheckInterval) as? Int ?? 60
        autoSwitch = defaults.object(forKey: Keys.autoSwitch) as? Bool ?? true
    }

    static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        guard let url = URL(string: text), url.host != nil else { return nil }
        return url
    }

    private enum Keys {
        static let siteURL = "siteURL"
        static let recheckInterval = "recheckInterval"
        static let autoSwitch = "autoSwitch"
    }
}
