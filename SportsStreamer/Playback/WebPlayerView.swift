import SwiftUI
import WebKit

/// Fallback: shows the embed page itself, with pop-ups and redirect ads blocked.
struct WebPlayerView: UIViewRepresentable {
    let url: URL
    let referer: URL?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.addUserScript(AdBlocker.popupBlockerScript)
        if let rules = AdBlocker.cachedRuleList { config.userContentController.add(rules) }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = HTMLFetcher.userAgent
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        context.coordinator.committedHost = nil
        var request = URLRequest(url: url)
        if let referer { request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer") }
        webView.load(request)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var loadedURL: URL?
        var committedHost: String?

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(AdBlocker.policy(for: action, committedHost: committedHost))
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            if committedHost == nil, let url = webView.url { committedHost = AdBlocker.bareHost(url) }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil
        }
    }
}
