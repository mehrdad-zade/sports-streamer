import UIKit
import WebKit

/// Loads an embed page in an invisible web view and watches every frame for an HLS manifest request.
@MainActor
final class StreamSniffer: NSObject {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<ResolvedStream?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var committedHost: String?
    private var reported = Set<String>()

    static func sniff(page: URL, referer: URL?, timeout: TimeInterval = 20) async -> ResolvedStream? {
        let sniffer = StreamSniffer()
        return await withTaskCancellationHandler {
            await sniffer.run(page: page, referer: referer, timeout: timeout)
        } onCancel: {
            Task { @MainActor in sniffer.finish(nil) }
        }
    }

    private func run(page: URL, referer: URL?, timeout: TimeInterval) async -> ResolvedStream? {
        if Task.isCancelled { return nil }
        let rules = await AdBlocker.ruleList()

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all // never make noise while probing
        let controller = WKUserContentController()
        controller.addUserScript(AdBlocker.popupBlockerScript)
        controller.addUserScript(WKUserScript(source: Self.hookScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        controller.add(WeakScriptHandler(self), name: "sniffer")
        if let rules { controller.add(rules) }
        config.userContentController = controller

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 225), configuration: config)
        webView.customUserAgent = HTMLFetcher.userAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isUserInteractionEnabled = false
        webView.alpha = 0.01
        Self.attachHidden(webView)
        self.webView = webView

        var request = URLRequest(url: page)
        if let referer { request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer") }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            webView.load(request)
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.finish(nil)
            }
        }
    }

    private func finish(_ stream: ResolvedStream?) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        if let webView {
            webView.stopLoading()
            webView.configuration.userContentController.removeAllScriptMessageHandlers()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.removeFromSuperview()
        }
        webView = nil
        continuation.resume(returning: stream)
    }

    private func validate(urlString: String, framePage: String?, userAgent: String?) async {
        guard continuation != nil, let url = URL(string: urlString), let webView else { return }
        let frameURL = framePage.flatMap(URL.init(string:))
        let origin = frameURL.flatMap { u -> String? in
            guard let scheme = u.scheme, let host = u.host else { return nil }
            return "\(scheme)://\(host)" + (u.port.map { ":\($0)" } ?? "")
        }
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies().filter { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return url.host?.hasSuffix(domain) ?? false
        }
        let ua = userAgent ?? HTMLFetcher.userAgent
        let attempts = [
            ResolvedStream(url: url, referer: frameURL.map { "\($0.scheme ?? "https")://\($0.host ?? "")/" }, origin: origin, userAgent: ua, cookies: cookies),
            ResolvedStream(url: url, referer: framePage, origin: origin, userAgent: ua, cookies: cookies),
            ResolvedStream(url: url, referer: nil, origin: nil, userAgent: ua, cookies: cookies),
        ]
        for stream in attempts {
            guard continuation != nil else { return }
            if await HTMLFetcher.isPlayableManifest(stream) {
                finish(stream)
                return
            }
        }
    }

    private static func attachHidden(_ view: UIView) {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return }
        // Behind all app content, but still "in a window" so WebKit runs timers and media code normally.
        window.insertSubview(view, at: 0)
    }

    /// Injected into every frame: reports any URL containing "m3u8" seen via fetch, XHR, media src or resource timing.
    private static let hookScript = """
    (function(){
      if (window.__ssHooked) return; window.__ssHooked = true;
      var seen = {};
      function report(u){
        try {
          if (!u) return; u = String(u);
          if (u.indexOf('blob:') === 0 || u.indexOf('data:') === 0) return;
          var abs = new URL(u, location.href).href;
          if (!/^https?:/i.test(abs) || !/m3u8/i.test(abs) || seen[abs]) return;
          seen[abs] = 1;
          window.webkit.messageHandlers.sniffer.postMessage({url: abs, page: location.href, ua: navigator.userAgent});
        } catch(e) {}
      }
      try { var of = window.fetch; if (of) window.fetch = function(i){ try { report(typeof i === 'string' ? i : (i && i.url)); } catch(e){} return of.apply(this, arguments); }; } catch(e){}
      try { var oo = XMLHttpRequest.prototype.open; XMLHttpRequest.prototype.open = function(m, u){ report(u); return oo.apply(this, arguments); }; } catch(e){}
      function hookSrc(proto){
        try {
          var d = Object.getOwnPropertyDescriptor(proto, 'src');
          Object.defineProperty(proto, 'src', { configurable: true,
            get: function(){ return d.get.call(this); },
            set: function(v){ report(v); return d.set.call(this, v); } });
        } catch(e){}
      }
      hookSrc(HTMLMediaElement.prototype); hookSrc(HTMLSourceElement.prototype);
      try { var sa = Element.prototype.setAttribute; Element.prototype.setAttribute = function(n, v){ if (n && String(n).toLowerCase() === 'src') report(v); return sa.apply(this, arguments); }; } catch(e){}
      var ticks = 0;
      setInterval(function(){
        ticks++;
        try { document.querySelectorAll('video, source').forEach(function(v){ report(v.currentSrc || v.src); if (v.tagName === 'VIDEO') v.muted = true; }); } catch(e){}
        try { performance.getEntriesByType('resource').forEach(function(e){ report(e.name); }); } catch(e){}
        if (ticks === 3 || ticks === 8) {
          // Some players only load the manifest after "play" is pressed.
          try {
            document.querySelectorAll('.vjs-big-play-button, .jw-icon-display, .jw-display-icon-container, .plyr__control--overlaid, .fp-play, .play-button, .playbtn, #play, [aria-label="Play"], video')
              .forEach(function(el){ try { el.click(); } catch(e){} });
            document.querySelectorAll('video').forEach(function(v){ v.muted = true; var p = v.play(); if (p && p.catch) p.catch(function(){}); });
          } catch(e){}
        }
      }, 700);
    })();
    """
}

extension StreamSniffer: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let url = body["url"] as? String,
              reported.insert(url).inserted else { return }
        let page = body["page"] as? String
        let ua = body["ua"] as? String
        Task { await validate(urlString: url, framePage: page, userAgent: ua) }
    }
}

extension StreamSniffer: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(AdBlocker.policy(for: action, committedHost: committedHost))
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if committedHost == nil, let url = webView.url { committedHost = AdBlocker.bareHost(url) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if committedHost == nil { finish(nil) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(nil)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        nil
    }
}
