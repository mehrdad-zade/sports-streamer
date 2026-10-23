import Foundation

/// Tiny regex-based helpers. The pages we scrape are simple enough that a full DOM parser isn't needed.
enum HTML {
    struct Match {
        let range: NSRange
        let groups: [String?]
    }

    static func matches(_ pattern: String, in text: String, options: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { result in
            let groups: [String?] = (0..<result.numberOfRanges).map { index in
                let r = result.range(at: index)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            return Match(range: result.range, groups: groups)
        }
    }

    static func firstGroup(_ pattern: String, in text: String) -> String? {
        matches(pattern, in: text).first?.groups.dropFirst().compactMap { $0 }.first
    }

    /// `(href, innerHTML)` of every `<a>` element.
    static func anchors(in html: String) -> [(href: String, inner: String)] {
        matches(#"<a\b[^>]*?\bhref\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#, in: html).compactMap { m in
            guard let href = m.groups[1] else { return nil }
            return (decodeEntities(href), m.groups[2] ?? "")
        }
    }

    /// Visible text chunks, in document order.
    static func textNodes(_ html: String) -> [String] {
        var text = html
        for pattern in [#"<script\b.*?</script>"#, #"<style\b.*?</style>"#, #"<svg\b.*?</svg>"#] {
            text = text.replacingOccurrences(of: pattern, with: "\n", options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
        return decodeEntities(text)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        let named = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&#039;": "'"]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
        for m in matches("&#(x?)([0-9a-f]+);", in: out).reversed() {
            let isHex = !(m.groups[1] ?? "").isEmpty
            guard let digits = m.groups[2], let code = UInt32(digits, radix: isHex ? 16 : 10),
                  let scalar = Unicode.Scalar(code) else { continue }
            out = (out as NSString).replacingCharacters(in: m.range, with: String(Character(scalar)))
        }
        return out
    }

    static func sameSite(_ a: URL, _ b: URL) -> Bool {
        func bare(_ u: URL) -> String { (u.host ?? "").lowercased().replacingOccurrences(of: "www.", with: "") }
        return bare(a) == bare(b)
    }

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let number = Double(raw) {
            return Date(timeIntervalSince1970: number > 1e11 ? number / 1000 : number)
        }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm"] {
            f.dateFormat = format
            if let d = f.date(from: raw) { return d }
        }
        return nil
    }
}
