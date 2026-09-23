import Foundation

enum SiteRequest: Sendable {
    case open(URL)                              // GET — click link / navigate
    case submit(URL, [String: String])          // POST — form submit
    case invoke(action: String, payload: [String: String])  // out-of-band action
    /// Player wants to open the native attachment picker for a compose draft.
    case composeAttach(requestId: String)
    /// Player removed an attachment from the compose draft.
    case composeRemoveAttachment(requestId: String, fileId: String)
}