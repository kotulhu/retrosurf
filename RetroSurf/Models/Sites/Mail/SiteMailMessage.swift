import Foundation

/// A file attached to a mail message. References a FileStore instance by id
/// and carries snapshot fields so the message renders even if the instance is
/// deleted or moved later — the transport never reads a real file.
struct MailAttachment: Codable, Sendable, Hashable {
    let instanceId: String
    /// files.su catalog file id this attachment points to.
    let contentId: String
    let fileName: String
    let sizeBytes: Int
    let hasVirus: Bool

    init(instanceId: String, contentId: String, fileName: String, sizeBytes: Int, hasVirus: Bool) {
        self.instanceId = instanceId
        self.contentId = contentId
        self.fileName = fileName
        self.sizeBytes = sizeBytes
        self.hasVirus = hasVirus
    }

    // Legacy drafts persisted a MailAttachment as {fileId, fileName, sizeBytes}
    // without an instanceId. Decoding is forgiving so old snapshots survive.
    enum CodingKeys: String, CodingKey {
        case instanceId, contentId, fileName, sizeBytes, hasVirus, fileId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacyFileId = try c.decodeIfPresent(String.self, forKey: .fileId)
        let contentId = try c.decodeIfPresent(String.self, forKey: .contentId) ?? legacyFileId ?? ""
        instanceId = try c.decodeIfPresent(String.self, forKey: .instanceId) ?? "legacy:\(contentId)"
        self.contentId = contentId
        fileName = try c.decode(String.self, forKey: .fileName)
        sizeBytes = try c.decode(Int.self, forKey: .sizeBytes)
        hasVirus = try c.decodeIfPresent(Bool.self, forKey: .hasVirus) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(instanceId, forKey: .instanceId)
        try c.encode(contentId, forKey: .contentId)
        try c.encode(fileName, forKey: .fileName)
        try c.encode(sizeBytes, forKey: .sizeBytes)
        try c.encode(hasVirus, forKey: .hasVirus)
    }
}

struct SiteMailMessage: Codable, Sendable, Identifiable {
    enum Folder: String, Codable, Sendable {
        case inbox, sent, drafts
    }

    init(id: Int, from: String, to: String, subject: String, bodyHTML: String, timestamp: Date, isRead: Bool, folder: Folder, tag: String?, attachments: [MailAttachment] = []) {
        self.id = id
        self.from = from
        self.to = to
        self.subject = subject
        self.bodyHTML = bodyHTML
        self.timestamp = timestamp
        self.isRead = isRead
        self.folder = folder
        self.tag = tag
        self.attachments = attachments
    }

    let id: Int
    let from: String
    let to: String
    let subject: String
    let bodyHTML: String
    let timestamp: Date
    var isRead: Bool
    var folder: Folder
    /// Opaque tag. When the message is read for the first time,
    /// MailSite emits `.setFlag("mail.read.\(tag)", true)`.
    var tag: String?
    /// Files attached by the player (sent folder) or received (inbox).
    /// Defaults to [] so legacy messages decode without the key.
    var attachments: [MailAttachment]

    enum CodingKeys: String, CodingKey {
        case id, from, to, subject, bodyHTML, timestamp, isRead, folder, tag, attachments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        from = try c.decode(String.self, forKey: .from)
        to = try c.decode(String.self, forKey: .to)
        subject = try c.decode(String.self, forKey: .subject)
        bodyHTML = try c.decode(String.self, forKey: .bodyHTML)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        isRead = try c.decode(Bool.self, forKey: .isRead)
        folder = try c.decode(Folder.self, forKey: .folder)
        tag = try c.decodeIfPresent(String.self, forKey: .tag)
        attachments = try c.decodeIfPresent([MailAttachment].self, forKey: .attachments) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(from, forKey: .from)
        try c.encode(to, forKey: .to)
        try c.encode(subject, forKey: .subject)
        try c.encode(bodyHTML, forKey: .bodyHTML)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(isRead, forKey: .isRead)
        try c.encode(folder, forKey: .folder)
        try c.encodeIfPresent(tag, forKey: .tag)
        try c.encode(attachments, forKey: .attachments)
    }
}