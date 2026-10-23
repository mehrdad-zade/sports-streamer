import WebKit

/// Shared ad/popup protection for every web view in the app.
@MainActor
enum AdBlocker {
    private static var cachedRules: WKContentRuleList?

    private static let blockedDomains = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "adservice.google.com", "popads.net", "popcash.net",
        "propellerads.com", "onclickads.net", "onclkds.com", "exoclick.com", "exosrv.com", "juicyads.com", "adcash.com",
        "hilltopads.net", "acscdn.com", "adsterra.com", "adsterratech.com", "clickadu.com", "monetag.com", "a-ads.com",
        "outbrain.com", "taboola.com", "adnxs.com", "mgid.com", "revcontent.com", "trafficjunky.net", "realsrv.com",
        "highperformanceformat.com", "profitabledisplaynetwork.com", "displayvertising.com", "bidgear.com", "ad-maven.com",
        "admaven.com", "pushwhy.com", "richads.com", "zeydoo.com", "galaksion.com", "clickaine.com", "dtscout.com",
        "histats.com", "yandex.ru/ads", "aclib.net", "magsrv.com", "popunder.net", "ezoic.net",
    ]

    /// Blocks ad networks plus pop-under scripts.
    static func ruleList() async -> WKContentRuleList? {
        if let cachedRules { return cachedRules }
        var rules: [[String: Any]] = blockedDomains.map { domain in
            let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
            return ["trigger": ["url-filter": "^https?://([^/]*\\.)?\(escaped)"], "action": ["type": "block"]]
        }
        rules.append(["trigger": ["url-filter": "(popunder|popads|/pop\\.js|runpop|clickunder)"], "action": ["type": "block"]])
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let json = String(data: data, encoding: .utf8) else { return nil }
        cachedRules = try? await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "adblock-v1", encodedContentRuleList: json)
        return cachedRules
    }

    static var cachedRuleList: WKContentRuleList? { cachedRules }

    /// Kills `window.open` so pop-ups/pop-unders never get a window.
    static let popupBlockerScript = WKUserScript(source: """
        (function(){
          try { window.open = function(){ return null; }; } catch(e) {}
          document.addEventListener('click', function(e){
            var a = e.target && e.target.closest ? e.target.closest('a[target=_blank]') : null;
            if (a) { e.preventDefault(); e.stopImmediatePropagation(); }
          }, true);
        })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false)

    /// Navigation policy: no new windows, no weird schemes, and once the page has committed,
    /// no top-level jumps to another host (the classic "click anywhere -> ad site" redirect).
    static func policy(for action: WKNavigationAction, committedHost: String?) -> WKNavigationActionPolicy {
        guard let url = action.request.url, let scheme = url.scheme?.lowercased() else { return .cancel }
        if ["about", "blob", "data"].contains(scheme) { return .allow }
        guard ["http", "https"].contains(scheme) else { return .cancel }
        guard let frame = action.targetFrame else { return .cancel }
        if frame.isMainFrame, let committedHost, bareHost(url) != committedHost { return .cancel }
        return .allow
    }

    static func bareHost(_ url: URL) -> String {
        (url.host ?? "").lowercased().replacingOccurrences(of: "www.", with: "")
    }
}

/// Avoids the WKUserContentController -> handler retain cycle.
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
