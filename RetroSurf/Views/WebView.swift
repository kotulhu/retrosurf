import SwiftUI
@preconcurrency import WebKit

struct WebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let reloadToken: Int
    let onNavigate: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(reloadToken: reloadToken, onNavigate: onNavigate)
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
        guard context.coordinator.lastToken != reloadToken else { return }
        context.coordinator.lastToken = reloadToken
        nsView.loadHTMLString(html, baseURL: baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastToken: Int
        var onNavigate: (String) -> Void

        init(reloadToken: Int, onNavigate: @escaping (String) -> Void) {
            self.lastToken = reloadToken
            self.onNavigate = onNavigate
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
            if url.scheme == "retrosurf" {
                onNavigate(url.host ?? url.absoluteString)
                decisionHandler(.cancel)
                return
            }
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
        }
    }
}