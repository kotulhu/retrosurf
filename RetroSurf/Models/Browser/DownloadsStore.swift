import Foundation

/// A download-in-progress record. The transfer runs in the browser against
/// the live modem speed; the store only tracks progress until `complete(_:)`
/// turns the record into a `FileInstance` in the downloads folder.
struct InFlightDownload: Identifiable, Sendable {
    enum Status: String, Sendable {
        case inProgress, completed, failed, cancelled
    }

    let id: String
    /// Catalog id of the source file (SiteDownload.id), stable across re-downloads.
    let contentId: String
    let fileName: String
    let sizeBytes: Int
    let sourceURL: URL
    let hasVirus: Bool
    /// Where the (simulated, never materialized) file would land.
    let targetURL: URL
    let startedAt: Date
    var status: Status
    var bytesSent: Int
}

/// Thin view over the downloads folder (via LocalFileStore) plus the in-flight
/// progress journal. `complete` is the only operation that mints a FileInstance
/// — the browser never writes to disk.
@MainActor
final class DownloadsStore: ObservableObject {
    /// The downloads folder node name in the FileStore ("local:Загрузки").
    /// Legacy instances still live in the plain "downloads" node and are
    /// read back as the same folder.
    static let nodeName = LocalFolder.downloads.ownerNode

    /// The real macOS Downloads folder that mirrors «Мои документы/Загрузки»
    /// on the file system. Stub files land here so finished downloads also
    /// exist outside the game.
    static var realDownloadsDirectoryURL: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private static let stubDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter
    }()

    @Published private(set) var inFlight: [InFlightDownload] = []

    private let fileStore: FileStore
    private let localFileStore: LocalFileStore
    private let bus: GameBus

    init(fileStore: FileStore, localFileStore: LocalFileStore, bus: GameBus) {
        self.fileStore = fileStore
        self.localFileStore = localFileStore
        self.bus = bus
    }

    // MARK: - In-flight downloads (progress tracking)

    /// Registers a new transfer. No FileInstance is created yet — that happens
    /// at `complete(_:)`.
    @discardableResult
    func start(_ download: SiteDownload, target: URL) -> InFlightDownload {
        let record = InFlightDownload(
            id: UUID().uuidString,
            contentId: download.id,
            fileName: download.fileName,
            sizeBytes: download.sizeBytes,
            sourceURL: download.sourceURL,
            hasVirus: download.hasVirus,
            targetURL: target,
            startedAt: Date(),
            status: .inProgress,
            bytesSent: 0
        )
        inFlight.append(record)
        return record
    }

    func updateProgress(_ id: String, fraction: Double, bytesSent: Int, bytesTotal: Int) {
        guard let index = inFlight.firstIndex(where: { $0.id == id }) else { return }
        inFlight[index].status = .inProgress
        inFlight[index].bytesSent = min(bytesSent, bytesTotal)
    }

    /// Finishes the transfer: mints a FileInstance in the downloads folder,
    /// drops the in-flight record and publishes `.fileDownloaded`.
    @discardableResult
    func complete(_ id: String) -> FileInstance? {
        guard let index = inFlight.firstIndex(where: { $0.id == id }) else { return nil }
        let record = inFlight.remove(at: index)
        let content = FileContent(
            contentId: record.contentId,
            name: record.fileName,
            sizeBytes: record.sizeBytes,
            hasVirus: record.hasVirus,
            virusKind: nil,
            sourceURL: record.sourceURL,
            downloadedAt: Date()
        )
        let instance = fileStore.create(content: content, ownerNode: Self.nodeName)
        writeStubFile(record: record)
        bus.publish(.fileDownloaded(
            FileDownloadedEvent(
                contentId: instance.content.contentId,
                instanceId: instance.instanceId,
                name: instance.content.name,
                sizeBytes: instance.content.sizeBytes,
                hasVirus: instance.content.hasVirus,
                downloadedAt: instance.content.downloadedAt
            )
        ))
        bus.publish(.bytesDownloaded(
            BytesDownloadedEvent(
                bytes: instance.content.sizeBytes,
                contentId: instance.content.contentId,
                occurredAt: instance.content.downloadedAt
            )
        ))
        return instance
    }

    /// Fails the transfer. The record is dropped (no history entry is kept).
    func fail(_ id: String) {
        inFlight.removeAll { $0.id == id }
    }

    /// Cancels the transfer. The record is dropped.
    func cancel(_ id: String) {
        inFlight.removeAll { $0.id == id }
    }

    // MARK: - Real file system (stub files)

    /// The real URL on disk where the stub for a given file name lives.
    /// Catalog names may contain characters invalid in macOS filenames —
    /// those are replaced so `diskURL` never throws.
    func diskURL(for fileName: String) -> URL {
        let safe = fileName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\0", with: "_")
        return Self.realDownloadsDirectoryURL.appendingPathComponent(safe)
    }

    /// Writes a small text stub so the finished download also exists on the
    /// real file system («маленькая текстовая заглушка»). Stub size in the
    /// game is the download's real size, but the disk copy is intentionally
    /// a placeholder — the catalog file itself never materializes.
    private func writeStubFile(record: InFlightDownload) {
        var name = record.fileName
        if name.isEmpty { name = String(record.id.prefix(8)) }
        let url = diskURL(for: name)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let text = """
        RetroSurf — симуляция загрузки
        Файл: \(record.fileName)
        Размер: \(record.sizeBytes) байт
        Источник: \(record.sourceURL.absoluteString)
        Скачано: \(Self.stubDateFormatter.string(from: record.startedAt))
        """
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Re-creates missing stub files for already completed downloads. Used
    /// after the FileStore graph is restored so downloads that predate a
    /// relaunch still have their real filesystem counterpart.
    func ensureStubFiles() {
        for file in completedFiles {
            let url = diskURL(for: file.content.name)
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            let text = """
            RetroSurf — симуляция загрузки
            Файл: \(file.content.name)
            Размер: \(file.content.sizeBytes) байт
            Источник: \(file.content.sourceURL.absoluteString)
            Скачано: \(Self.stubDateFormatter.string(from: file.content.downloadedAt))
            """
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Completed files (read from LocalFileStore)

    /// Completed files in the downloads folder, newest first.
    var completedFiles: [FileInstance] {
        localFileStore.files(in: .downloads)
    }

    /// Files in the downloads folder that are safe to attach (no virus).
    func attachableFiles() -> [FileInstance] {
        localFileStore.files(in: .downloads).filter { !$0.content.hasVirus }
    }

    /// Look up in the downloads folder by contentId.
    func completedFile(withContentId contentId: String) -> FileInstance? {
        localFileStore.files(in: .downloads)
            .first { $0.content.contentId == contentId }
    }

    /// Clears the download journal: every downloads-folder instance is removed
    /// (publishing `.fileRemoved` per copy), in-flight transfers are dropped.
    func clearAll() {
        let ids = localFileStore.files(in: .downloads).map(\.instanceId)
        for id in ids {
            _ = fileStore.remove(instanceId: id)
        }
        inFlight.removeAll()
    }
}