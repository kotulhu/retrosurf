import Foundation

/// Loads the per-category "generated" bulk file sets that lift a site's catalog
/// from a handful of hand-written featured tracks up to a realistically full
/// archive. Each category folder under `basePath` holds an `_meta.json`
/// (`{totalEntries, chunkSize, chunkCount}`) plus `chunk_000.json …` arrays of
/// `FilesFile`. A missing or broken folder is skipped — never a crash.
struct FilesBulkLoader: Sendable {
    static let empty = FilesBulkLoader(entriesByCategory: [:])

    /// Category id → generated file entries (already concatenated from chunks).
    let entriesByCategory: [String: [FilesFile]]

    /// Loads bulk files from a bundle directory relative to the resources root,
    /// e.g. `Sites/melodia.su/generated`. Returns `.empty` when absent.
    static func loadFromBundle(basePath: String) -> FilesBulkLoader {
        guard let base = Bundle.main.resourceURL?.appendingPathComponent(basePath) else {
            return .empty
        }
        return load(from: base)
    }

    /// Loads all generated subfolders under `baseDirectory` (used by the app
    /// and the deterministic-content harness alike).
    static func load(from baseDirectory: URL) -> FilesBulkLoader {
        let fileManager = FileManager.default
        guard let ids = try? fileManager.contentsOfDirectory(atPath: baseDirectory.path) else {
            return .empty
        }
        var result: [String: [FilesFile]] = [:]
        for id in ids.sorted() {
            if id.hasPrefix(".") { continue }
            let directory = baseDirectory.appendingPathComponent(id)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            guard let metaData = try? Data(contentsOf: directory.appendingPathComponent("_meta.json")),
                  let meta = try? JSONDecoder().decode(BulkMeta.self, from: metaData),
                  meta.totalEntries > 0 else {
                continue
            }
            var entries: [FilesFile] = []
            for chunk in 0..<max(1, meta.chunkCount) {
                let chunkURL = directory.appendingPathComponent(String(format: "chunk_%03d.json", chunk))
                guard let data = try? Data(contentsOf: chunkURL),
                      let files = try? JSONDecoder().decode([FilesFile].self, from: data) else {
                    break
                }
                entries.append(contentsOf: files)
            }
            result[id] = entries
        }
        return FilesBulkLoader(entriesByCategory: result)
    }

    func entries(for categoryID: String) -> [FilesFile] {
        entriesByCategory[categoryID] ?? []
    }

    /// First generated file matching `id`, across every category.
    func file(withId id: String) -> (categoryID: String, file: FilesFile)? {
        for (categoryID, files) in entriesByCategory {
            if let file = files.first(where: { $0.id == id }) {
                return (categoryID, file)
            }
        }
        return nil
    }

    private struct BulkMeta: Decodable, Sendable {
        let totalEntries: Int
        let chunkSize: Int
        let chunkCount: Int
    }
}