import Foundation

/// A playable media URL plus the HTTP context needed to fetch it outside the web view.
struct ResolvedStream: Hashable {
    let url: URL
    let referer: String?
    let origin: String?
    let userAgent: String
    let cookies: [HTTPCookie]

    var httpHeaders: [String: String] {
        var headers = ["User-Agent": userAgent]
        if let referer { headers["Referer"] = referer }
        if let origin { headers["Origin"] = origin }
        return headers
    }
}

struct StreamSource: Identifiable, Hashable {
    enum Status: Hashable {
        case unknown
        case checking
        case alive(ResolvedStream)
        case dead
    }

    let id: Int
    /// The link exactly as it appeared on the event page (may be a wrapper page).
    let pageURL: URL
    /// The unwrapped embed URL (same as `pageURL` when there was no wrapper).
    let embedURL: URL
    let label: String
    var status: Status = .unknown
    var lastChecked: Date?

    var host: String { embedURL.host?.replacingOccurrences(of: "www.", with: "") ?? embedURL.absoluteString }

    var resolved: ResolvedStream? {
        if case .alive(let stream) = status { return stream }
        return nil
    }

    var isAlive: Bool { resolved != nil }
}
