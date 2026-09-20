import Foundation
import WebKit

final class ThrottledSchemeHandler: NSObject, WKURLSchemeHandler {
    var reportTraffic: ((_ sent: Int, _ received: Int) -> Void)?

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        reportTraffic?(0, 0)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
    }
}