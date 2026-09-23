import Foundation

/// One pre-installed file template from Resources/Files/preinstalled.json.
struct PreinstalledFileTemplate: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let sizeBytes: Int
    let description: String
    let hasVirus: Bool
}

/// Loads the pre-installed files catalog from the bundle.
struct PreinstalledFilesCatalog: Codable, Sendable {
    let files: [PreinstalledFileTemplate]

    static func loadFromBundle(named name: String = "preinstalled") -> PreinstalledFilesCatalog {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("[PreinstalledFiles] failed to load \(name).json from bundle")
            return PreinstalledFilesCatalog(files: [])
        }
        do {
            return try JSONDecoder().decode(PreinstalledFilesCatalog.self, from: data)
        } catch {
            print("[PreinstalledFiles] decode error for \(name).json: \(error)")
            return PreinstalledFilesCatalog(files: [])
        }
    }
}

/// Creates FileInstances for the pre-installed files in the "local:Мои документы"
/// node. Idempotent — a content id already present in that node is skipped, so
/// running `install` twice never duplicates. No bus events are fired: these
/// files were always there, nobody "downloaded" them.
@MainActor
enum PreinstalledFilesInstaller {
    static func install(catalog: PreinstalledFilesCatalog, fileStore: FileStore) {
        let documentsNode = LocalFolder.documents.ownerNode
        for template in catalog.files {
            let alreadyInstalled = fileStore.instances(withContentId: template.id)
                .contains { $0.ownerNode == documentsNode }
            guard !alreadyInstalled else { continue }
            let content = FileContent(
                contentId: template.id,
                name: template.name,
                sizeBytes: template.sizeBytes,
                hasVirus: template.hasVirus,
                virusKind: nil,
                sourceURL: URL(string: "file:///C:/Мои документы/\(template.name)")!,
                downloadedAt: Date()
            )
            _ = fileStore.create(content: content, ownerNode: documentsNode)
        }
    }
}