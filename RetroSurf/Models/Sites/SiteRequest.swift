import Foundation

enum SiteRequest: Sendable {
    case open(URL)                              // GET — click link / navigate
    case submit(URL, [String: String])          // POST — form submit
    case invoke(action: String, payload: [String: String])  // out-of-band action
}