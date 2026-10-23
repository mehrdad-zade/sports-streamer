import Foundation

struct Event: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let title: String
    let subtitle: String?
    let teams: [String]
    let start: Date?
    let end: Date?
    let statusText: String?
    var sport: String?

    var isLive: Bool {
        if let start {
            let now = Date()
            let end = end ?? start.addingTimeInterval(3 * 3600)
            return now >= start.addingTimeInterval(-10 * 60) && now <= end
        }
        return statusText?.localizedCaseInsensitiveContains("live") ?? false
    }

    var hasEnded: Bool {
        guard let end else { return false }
        return Date() > end
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        let text = ([title, subtitle ?? "", sport ?? ""] + teams).joined(separator: " ")
        let haystack = text + " " + Self.sportAliases(for: text)
        // Every word of the query must appear somewhere ("real bet" -> Real Betis).
        return q.split(separator: " ").allSatisfy { haystack.localizedStandardContains($0) }
    }

    /// Sites label categories tersely ("SOCCER", "NBA", "F1"); let people search by the sport's everyday names too.
    private static let aliases: [(keys: [String], terms: String)] = [
        (["soccer", "football"], "soccer football"),
        (["nba", "wnba", "basketball"], "basketball"),
        (["nfl", "ncaaf"], "american football"),
        (["nhl", "hockey"], "hockey ice hockey"),
        (["ufc", "mma"], "mma fighting"),
        (["boxing"], "fight fighting"),
        (["mlb", "baseball"], "baseball"),
        (["f1", "formula 1", "motogp", "grand prix", "nascar", "indycar"], "motorsport racing formula"),
    ]

    private static func sportAliases(for text: String) -> String {
        let words = Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let lower = text.lowercased()
        return aliases
            .filter { $0.keys.contains { $0.contains(" ") ? lower.contains($0) : words.contains($0) } }
            .map(\.terms)
            .joined(separator: " ")
    }
}
