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
        let haystack = ([title, subtitle ?? "", sport ?? ""] + teams).joined(separator: " ")
        // Every word of the query must appear somewhere ("real bet" -> Real Betis).
        return q.split(separator: " ").allSatisfy { haystack.localizedStandardContains($0) }
    }
}
