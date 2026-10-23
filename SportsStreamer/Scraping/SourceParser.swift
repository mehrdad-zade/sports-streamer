import Foundation

/// Extracts candidate stream/embed links from an event page.
enum SourceParser {
    private static let blockedHosts = ["discord", "t.me", "telegram", "twitter.com", "x.com", "facebook", "instagram", "reddit",
                                       "tiktok", "whatsapp", "google", "gstatic", "cloudflare", "jsdelivr", "unpkg", "schema.org",
                                       "w3.org", "apple.com", "wikipedia", "youtube.com/@"]
    private static let assetExtensions: Set<String> = ["css", "js", "png", "jpg", "jpeg", "gif", "webp", "svg", "ico", "woff", "woff2", "ttf", "json", "xml", "txt", "map"]
    private static let streamHint = #"(embed|stream|player|live|watch|channel|/ch\b|[?&]ch=|/ch\d|\.php|hls|m3u8|ppv|/tv\b|event|/e/|/v/)"#
    private static let buttonText = #"^(watch|watch now|play|go|open|link|stream|view|click here|▶)$"#

    private struct Candidate {
        let page: URL
        let embed: URL
        let wrapped: Bool
        let position: Int
    }

    static func parse(html: String, pageURL: URL) -> [StreamSource] {
        let rows = HTML.matches(#"<tr\b[^>]*>(.*?)</tr>"#, in: html).map { m -> (NSRange, String?) in
            let label = HTML.textNodes(m.groups[1] ?? "").first {
                $0.range(of: buttonText, options: [.regularExpression, .caseInsensitive]) == nil && $0.count > 1
            }
            return (m.range, label)
        }

        var candidates: [Candidate] = []
        let attr = #"\b(?:href|src|data-src|data-url|data-link|data-iframe|data-stream|data-embed)\s*=\s*["']([^"'<>\s]+)["']"#
        for m in HTML.matches(attr, in: html) {
            guard let raw = m.groups[1].map(HTML.decodeEntities),
                  let page = URL(string: raw, relativeTo: pageURL)?.absoluteURL,
                  ["http", "https"].contains(page.scheme?.lowercased() ?? "") else { continue }
            let embed = unwrap(page)
            let wrapped = embed != page
            guard isCandidate(embed, pageURL: pageURL, wrapped: wrapped) else { continue }
            candidates.append(Candidate(page: page, embed: embed, wrapped: wrapped, position: m.range.location))
        }

        let strong = candidates.filter { $0.wrapped || hasStreamHint($0.embed) }
        let chosen = strong.isEmpty ? candidates : strong

        var seen = Set<String>()
        var sources: [StreamSource] = []
        for c in chosen {
            let key = c.embed.absoluteString.lowercased()
            guard seen.insert(key).inserted else { continue }
            let rowLabel = rows.first { NSLocationInRange(c.position, $0.0) }?.1
            let host = c.embed.host?.replacingOccurrences(of: "www.", with: "") ?? "source"
            sources.append(StreamSource(id: sources.count, pageURL: c.page, embedURL: c.embed, label: rowLabel ?? host))
        }

        if sources.isEmpty {
            // Some sites embed the player directly on the event page.
            sources.append(StreamSource(id: 0, pageURL: pageURL, embedURL: pageURL, label: "Event page"))
        }
        return sources
    }

    /// `https://wrapper/view.php?src=https://embed/x?id=1` -> `https://embed/x?id=1` (also handles percent/base64 encoding).
    static func unwrap(_ url: URL) -> URL {
        guard let query = URLComponents(url: url, resolvingAgainstBaseURL: true)?.percentEncodedQuery else { return url }
        if let range = query.range(of: #"=(https?(:|%3A)[^\s]*)"#, options: [.regularExpression, .caseInsensitive]) {
            var value = String(query[range].dropFirst())
            if value.lowercased().hasPrefix("http%3a") { value = value.removingPercentEncoding ?? value }
            if let inner = URL(string: value), inner.host != nil { return unwrap(inner) }
        }
        for item in URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems ?? [] {
            guard let v = item.value, v.hasPrefix("aHR0c") else { continue }
            var b64 = v
            while b64.count % 4 != 0 { b64 += "=" }
            if let data = Data(base64Encoded: b64), let s = String(data: data, encoding: .utf8),
               let inner = URL(string: s), inner.host != nil { return unwrap(inner) }
        }
        return url
    }

    private static func isCandidate(_ url: URL, pageURL: URL, wrapped: Bool) -> Bool {
        let full = url.absoluteString.lowercased()
        if blockedHosts.contains(where: { full.contains($0) }) { return false }
        if assetExtensions.contains(url.pathExtension.lowercased()) { return false }
        if HTML.sameSite(url, pageURL) {
            // Same-site links are navigation, unless they clearly point at a player.
            return !wrapped && url.path.lowercased().range(of: #"(embed|player|/stream/)"#, options: .regularExpression) != nil
        }
        return true
    }

    private static func hasStreamHint(_ url: URL) -> Bool {
        url.absoluteString.lowercased().range(of: streamHint, options: .regularExpression) != nil
    }
}
