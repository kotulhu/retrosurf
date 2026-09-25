import Foundation

struct SiteDescriptor: Codable, Hashable, Sendable {
    let id: String          // e.g. "mail", "dating"
    let host: String        // e.g. "mail.su", "love.mail.su"
    let displayName: String
    let iconSystemName: String  // SF Symbol for tab / bookmark
}