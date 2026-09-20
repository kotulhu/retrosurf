import SwiftUI
@preconcurrency import WebKit

struct WebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let reloadToken: Int
    let onNavigate: (String) -> Void
    var isInteractiveHost: (String) -> Bool = { _ in false }

    func makeCoordinator() -> Coordinator {
        Coordinator(reloadToken: reloadToken, onNavigate: onNavigate, isInteractiveHost: isInteractiveHost)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(html, baseURL: baseURL)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onNavigate = onNavigate
        context.coordinator.isInteractiveHost = isInteractiveHost
        guard context.coordinator.lastToken != reloadToken else { return }
        context.coordinator.lastToken = reloadToken
        nsView.loadHTMLString(html, baseURL: baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastToken: Int
        var onNavigate: (String) -> Void
        var isInteractiveHost: (String) -> Bool

        init(reloadToken: Int, onNavigate: @escaping (String) -> Void, isInteractiveHost: @escaping (String) -> Bool) {
            self.lastToken = reloadToken
            self.onNavigate = onNavigate
            self.isInteractiveHost = isInteractiveHost
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            // Interactive sites speak the retrosurf:// dialect inside their pages.
            if url.scheme == "retrosurf" {
                onNavigate(url.absoluteString)
                decisionHandler(.cancel)
                return
            }
            // http:// links/forms that lead to a registered interactive host
            // (pochta.su...) are routed back into the browser layer. GET form
            // submissions carry the fields in the query string, which is how
            // the browser parses them into [String: String].
            if url.scheme == "http" || url.scheme == "https" {
                if navigationAction.navigationType != .other,
                   let host = url.host,
                   isInteractiveHost(host) {
                    onNavigate(url.absoluteString)
                    decisionHandler(.cancel)
                    return
                }
            }
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
                return
            }
            // Everything else (external http, file://, ...) is blocked.
            decisionHandler(.cancel)
        }
    }
}