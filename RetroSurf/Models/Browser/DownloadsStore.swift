import Foundation

struct DownloadedFile: Identifiable, Sendable {
    enum Status: String, Sendable {
        case inProgress, completed, cancelled, failed
    }

    let id: String
    let fileName: String
    let sizeBytes: Int
    let sourceURL: URL
    let startedAt: Date
    var status: Status
    var bytesSent: Int
    var virusDetected: Bool

    /// Kept so a completed item can re-trigger the full download flow.
    let source: SiteDownload
}

/// The simulated download journal. Holds only the record — the browser drives
/// the actual transfer against the live modem speed.
@MainActor
final class DownloadsStore: ObservableObject {
    @Published private(set) var items: [DownloadedFile] = []

    @discardableResult
    func start(_ download: SiteDownload) -> DownloadedFile {
        let record = DownloadedFile(
            id: UUID().uuidString,
            fileName: download.fileName,
            sizeBytes: download.sizeBytes,
            sourceURL: download.sourceURL,
            startedAt: Date(),
            status: .inProgress,
            bytesSent: 0,
            virusDetected: false,
            source: download
        )
        items.append(record)
        return record
    }

    func updateProgress(_ id: String, fraction: Double, bytesSent: Int, bytesTotal: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = .inProgress
        items[index].bytesSent = bytesSent
    }

    func complete(_ id: String, virusDetected: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = .completed
        items[index].bytesSent = items[index].sizeBytes
        items[index].virusDetected = virusDetected
    }

    func fail(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = .failed
    }

    func cancel(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = .cancelled
    }

    func clearAll() {
        items.removeAll()
    }
}