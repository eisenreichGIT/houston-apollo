import SwiftUI
import WebKit

/// Houston itself, full screen: the same app as in Safari, served by your Apollo.
struct HoustonScreen: View {
    @EnvironmentObject var store: Store
    @State private var showSettings = false
    @State private var pairToken: String?

    var body: some View {
        HoustonWebView(base: store.base ?? "", onSettings: { showSettings = true }, onSignedIn: { token in
            if store.key == nil && !store.askedForKey { store.askedForKey = true; pairToken = token }
        })
        .ignoresSafeArea(edges: .bottom)
        .background(Color(red: 0.06, green: 0.063, blue: 0.05))
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store) }
        .alert("Turn on Siri and shortcuts?", isPresented: Binding(get: { pairToken != nil }, set: { if !$0 { pairToken = nil } })) {
            Button("Turn on") { if let t = pairToken { Task { await pair(t) } } }
            Button("Not now", role: .cancel) { }
        } message: {
            Text("Lets you say “Hey Siri, Houston status” or switch modes by voice, using Houston's shortcut key.")
        }
    }

    private func pair(_ token: String) async {
        guard let base = store.base else { return }
        if let key = try? await HoustonAPI(base: base).pair(token: token) { store.key = key }
    }
}

struct HoustonWebView: UIViewRepresentable {
    let base: String
    let onSettings: () -> Void
    let onSignedIn: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = "HoustonApp/1.0 (iOS)"
        config.userContentController.add(context.coordinator, name: "houston")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 0.06, green: 0.063, blue: 0.05, alpha: 1)
        web.allowsBackForwardNavigationGestures = true
        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.reload(_:)), for: .valueChanged)
        web.scrollView.refreshControl = refresh
        if let url = URL(string: base + "/") { web.load(URLRequest(url: url)) }
        context.coordinator.web = web
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) { }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let parent: HoustonWebView
        weak var web: WKWebView?
        init(_ p: HoustonWebView) { parent = p }

        @objc func reload(_ sender: UIRefreshControl) {
            if let url = URL(string: parent.base + "/"), web?.url == nil || web?.url?.host != url.host { web?.load(URLRequest(url: url)) } else { web?.reload() }
            sender.endRefreshing()
        }

        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
            if (message.body as? String) == "settings" { parent.onSettings() }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .allow }
            let home = URL(string: parent.base)?.host
            if url.host == home || url.scheme == "about" || url.scheme == "blob" { return .allow }
            _ = await UIApplication.shared.open(url)    // other sites (news, GitHub, wallets) open outside the app
            return .cancel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("(function(){try{return localStorage.getItem('apolloToken')}catch(e){return null}})()") { v, _ in
                if let t = v as? String, !t.isEmpty { self.parent.onSignedIn(t) }
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let e = error as NSError
            if e.code == NSURLErrorCancelled || (e.domain == "WebKitErrorDomain" && e.code == 102) { return }   // not a real failure
            let html = """
            <html><head><meta name='viewport' content='width=device-width,initial-scale=1'></head>
            <body style='background:#0F100D;color:#EEEAE0;font-family:-apple-system;padding:28px'>
            <h2>Can't reach Houston</h2><p style='color:#9A968B'>At home, check that this iPhone is on your Wi-Fi; away from home, turn on Tailscale.
            Pull down to retry, or change the address in the app's settings.</p>
            <p><a style='color:#F7931A' href='#' onclick="webkit.messageHandlers.houston.postMessage('settings');return false">App settings</a></p></body></html>
            """
            webView.loadHTMLString(html, baseURL: URL(string: parent.base + "/"))
        }
    }
}
