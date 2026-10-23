import Foundation

enum HTMLFetcher {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = ["User-Agent": userAgent, "Accept-Language": "en-US,en;q=0.9"]
        return URLSession(configuration: config)
    }()

    /// Returns the page HTML and the final URL after redirects.
    static func fetch(_ url: URL, referer: URL? = nil) async throws -> (html: String, finalURL: URL) {
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if let referer { request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer") }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return (html, response.url ?? url)
    }

    /// Lightweight liveness check for an HLS manifest.
    static func isPlayableManifest(_ stream: ResolvedStream) async -> Bool {
        var request = URLRequest(url: stream.url, timeoutInterval: 10)
        stream.httpHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        if !stream.cookies.isEmpty {
            HTTPCookie.requestHeaderFields(with: stream.cookies).forEach { request.setValue($1, forHTTPHeaderField: $0) }
        }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return false }
        let prefix = String(decoding: data.prefix(64), as: UTF8.self)
        if stream.url.absoluteString.lowercased().contains("m3u8") || prefix.contains("#EXTM3U") {
            return prefix.contains("#EXTM3U")
        }
        return !data.isEmpty
    }
}
