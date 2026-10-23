import Foundation

/// Heuristically extracts event links from a listing page.
enum EventListParser {
    private static let eventPathPrefixes: Set<String> = ["event", "events", "match", "matches", "watch", "live", "game", "games", "stream", "streams", "fixture", "fixtures"]
    private static let nonCategoryPaths: Set<String> = ["news", "blog", "about", "contact", "dmca", "privacy", "privacy-policy", "terms", "faq", "login", "register", "signup", "daily", "schedule", "sitemap", "search", "tos", "disclaimer"]
    private static let noiseText = #"^(view|watch|watch now|vs\.?|v|live|live now!?|hd|sd|more|details|go|-|:)$"#
    private static let statusText = #"(live|starts? in|started|ended|finished|full ?time|half ?time|postponed|cancel+ed|^\d{1,2}:\d{2}(:\d{2})?( ?[ap]m)?$|^\d+'$)"#

    static func parse(html: String, pageURL: URL, sport: String? = nil) -> [Event] {
        var byURL: [String: Event] = [:]
        var order: [String] = []

        for anchor in HTML.anchors(in: html) {
            guard let url = URL(string: anchor.href, relativeTo: pageURL)?.absoluteURL,
                  HTML.sameSite(url, pageURL), looksLikeEvent(url) else { continue }
            let event = makeEvent(url: stripFragment(url), inner: anchor.inner, sport: sport)
            let key = event.url.absoluteString
            if let existing = byURL[key] {
                if event.teams.count > existing.teams.count || (existing.start == nil && event.start != nil) {
                    byURL[key] = event
                }
            } else {
                byURL[key] = event
                order.append(key)
            }
        }
        return order.compactMap { byURL[$0] }
    }

    /// Same-site single-segment links that look like sport categories (e.g. /football, /nba).
    static func categoryLinks(html: String, pageURL: URL) -> [(url: URL, name: String)] {
        var seen = Set<String>()
        var result: [(URL, String)] = []
        for anchor in HTML.anchors(in: html) {
            guard let url = URL(string: anchor.href, relativeTo: pageURL)?.absoluteURL,
                  HTML.sameSite(url, pageURL), !looksLikeEvent(url) else { continue }
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count == 1, let slug = parts.first?.lowercased(),
                  !nonCategoryPaths.contains(slug), !slug.contains("."), url.query == nil else { continue }
            let text = HTML.textNodes(anchor.inner).joined(separator: " ")
            guard !text.isEmpty, text.count <= 24 else { continue }
            if seen.insert(slug).inserted { result.append((stripFragment(url), text)) }
        }
        return Array(result.prefix(15))
    }

    static func looksLikeEvent(_ url: URL) -> Bool {
        let parts = url.pathComponents.filter { $0 != "/" }.map { $0.lowercased() }
        guard let first = parts.first else { return false }
        if parts.count >= 2 && eventPathPrefixes.contains(first) { return true }
        let path = url.path.lowercased()
        return path.contains("-vs-") || path.contains("_vs_") || path.contains("-v-")
    }

    private static func makeEvent(url: URL, inner: String, sport: String?) -> Event {
        let start = HTML.parseDate(HTML.firstGroup(#"data-(?:start|start-time|time|date|timestamp)\s*=\s*["']([^"']+)["']"#, in: inner)
                                   ?? HTML.firstGroup(#"datetime\s*=\s*["']([^"']+)["']"#, in: inner))
        let end = HTML.parseDate(HTML.firstGroup(#"data-(?:end|end-time)\s*=\s*["']([^"']+)["']"#, in: inner))

        let texts = HTML.textNodes(inner)
        let status = texts.first { $0.range(of: statusText, options: [.regularExpression, .caseInsensitive]) != nil }

        // Prefer logo alt texts ("Real Madrid Logo"), fall back to visible text.
        var teams = HTML.matches(#"<img\b[^>]*\balt\s*=\s*["']([^"']+)["']"#, in: inner)
            .compactMap { $0.groups[1] }
            .map { HTML.decodeEntities($0).replacingOccurrences(of: #"\s*(logo|icon|badge|flag)$"#, with: "", options: [.regularExpression, .caseInsensitive]) }
            .filter { !$0.isEmpty && $0.range(of: noiseText, options: [.regularExpression, .caseInsensitive]) == nil }
        if teams.isEmpty {
            teams = texts.filter {
                $0 != status &&
                $0.range(of: noiseText, options: [.regularExpression, .caseInsensitive]) == nil &&
                $0.count > 1
            }
            // "Team A vs Team B" in a single node.
            if teams.count == 1, let split = splitVersus(teams[0]) { teams = split }
        }
        teams = teams.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }

        let isVersus = url.path.lowercased().contains("vs") || teams.count == 2 && texts.contains { $0.lowercased().hasPrefix("vs") }
        let title: String
        var subtitle: String?
        if teams.count >= 2 && isVersus {
            title = "\(teams[0]) vs \(teams[1])"
        } else if let first = teams.first {
            title = first
            subtitle = teams.count > 1 ? teams.dropFirst().joined(separator: " · ") : nil
        } else {
            title = humanize(url.lastPathComponent)
        }

        return Event(url: url, title: title, subtitle: subtitle, teams: teams, start: start, end: end, statusText: status, sport: sport)
    }

    private static func splitVersus(_ text: String) -> [String]? {
        let parts = text.components(separatedBy: " vs ").flatMap { $0.components(separatedBy: " v ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parts.count == 2 ? parts : nil
    }

    private static func humanize(_ slug: String) -> String {
        slug.replacingOccurrences(of: "-vs-", with: " vs ")
            .replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map { $0 == "vs" ? "vs" : $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static func stripFragment(_ url: URL) -> URL {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url }
        c.fragment = nil
        return c.url ?? url
    }
}
