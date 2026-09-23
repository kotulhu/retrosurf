import Foundation

struct FilesState: Codable, Sendable {
    var downloadCounts: [String: Int] = [:]
}

struct FilesSiteMeta: Codable, Sendable {
    let title: String
    let tagline: String
    let warning: String
    let footer: String
    let navLabel: String
}

struct FilesCategory: Codable, Sendable {
    let id: String
    let title: String
    let description: String
    let files: [FilesFile]
}

struct FilesFile: Codable, Sendable {
    let id: String
    let name: String
    let sizeBytes: Int
    let description: String
    let hasVirus: Bool
}

/// Fully data-driven archive catalog. The main `catalog.json` describes the
/// site plus a per-category index; every category's files live in their own
/// JSON file (`categories/<id>.json`). Nothing is hardcoded in Swift.
struct FilesCatalog: Codable, Sendable {
    static var emptyFallback: FilesCatalog {
        FilesCatalog(site: FilesSiteMeta.emptyFallback, categories: [])
    }

    let site: FilesSiteMeta
    let categories: [FilesCategory]

    /// On-disk shape of the main catalog: site meta + category index.
    private struct FilesCatalogIndex: Decodable {
        let site: FilesSiteMeta
        let categories: [FilesCategoryRef]
    }

    private struct FilesCategoryRef: Decodable {
        let id: String
        let file: String
    }

    static func loadFromBundle() -> FilesCatalog {
        for candidate in [
            Bundle.main.url(forResource: "catalog", withExtension: "json",
                            subdirectory: "sites/files.su"),
            Bundle.main.url(forResource: "catalog", withExtension: "json",
                            subdirectory: "sites"),
            Bundle.main.resourceURL?.appendingPathComponent("sites/files.su/catalog.json"),
        ] {
            guard let candidate else { continue }
            let catalog = load(catalogAt: candidate)
            if !catalog.site.title.isEmpty {
                return catalog
            }
        }
        return .emptyFallback
    }

    /// Loads the split archive: reads the category index from `catalogURL`,
    /// then resolves each referenced category file relative to it. A missing
    /// or broken category file is skipped rather than crashing the app.
    static func load(catalogAt catalogURL: URL) -> FilesCatalog {
        guard let data = try? Data(contentsOf: catalogURL) else {
            return .emptyFallback
        }
        if let index = try? JSONDecoder().decode(FilesCatalogIndex.self, from: data) {
            let base = catalogURL.deletingLastPathComponent()
            var categories: [FilesCategory] = []
            for ref in index.categories {
                guard let fileData = try? Data(contentsOf: base.appendingPathComponent(ref.file)),
                      let category = try? JSONDecoder().decode(FilesCategory.self, from: fileData),
                      category.id == ref.id else {
                    continue
                }
                categories.append(category)
            }
            return FilesCatalog(site: index.site, categories: categories)
        }
        // Legacy single-file format (site + inline categories in one JSON).
        if let legacy = try? JSONDecoder().decode(FilesCatalog.self, from: data) {
            return legacy
        }
        return .emptyFallback
    }

    func file(withId id: String) -> (category: FilesCategory, file: FilesFile)? {
        for category in categories {
            if let file = category.files.first(where: { $0.id == id }) {
                return (category, file)
            }
        }
        return nil
    }
}

extension FilesSiteMeta {
    /// Truly empty fallback so the bundle never crashes the app. Renders as a
    /// nearly blank page rather than inventing player-facing copy in Swift.
    static let emptyFallback = FilesSiteMeta(
        title: "Files.su",
        tagline: "",
        warning: "",
        footer: "",
        navLabel: ""
    )
}

@MainActor
final class FilesSite: BaseInteractiveSite<FilesState> {
    static let host = "files.su"

    private let catalog: FilesCatalog

    init(catalog: FilesCatalog) {
        self.catalog = catalog
        super.init(
            descriptor: SiteDescriptor(
                id: "files",
                host: Self.host,
                displayName: "Files.su",
                iconSystemName: "square.and.arrow.down"
            ),
            initialState: FilesState()
        )
    }

    override func resetGameplay() {
        state = FilesState()
    }

    override func handle(_ request: SiteRequest) async -> SiteResponse {
        switch request {
        case .open(let url):
            return handleGet(url)
        case .submit(let url, _):
            return handleGet(url)
        case .invoke(let action, _):
            return .failure("404: \(action)")
        }
    }

    // MARK: - Routing

    private func handleGet(_ url: URL) -> SiteResponse {
        guard let host = url.host?.lowercased(), host == Self.host else {
            return .failure("Host not found: \(url.host ?? url.absoluteString)")
        }
        let path = url.path.isEmpty ? "/" : url.path
        if path == "/" { return indexPage() }
        if path.hasPrefix("/category/") {
            return categoryPage(String(path.dropFirst("/category/".count)))
        }
        if path.hasPrefix("/download/") {
            return downloadResponse(String(path.dropFirst("/download/".count)))
        }
        return .failure("404: \(path)")
    }

    // MARK: - Pages

    private func indexPage() -> SiteResponse {
        let site = catalog.site
        let categoryLinks = catalog.categories
            .map { "<a href=\"\(resolve("/category/\($0.id)"))\">\(esc($0.title))</a>" }
            .joined(separator: " · ")
        var nav = ""
        if !site.navLabel.isEmpty, !categoryLinks.isEmpty {
            nav = "<p class=\"nav\"><b>\(esc(site.navLabel)):</b> \(categoryLinks)</p>\n"
        }
        var rows = ""
        for category in catalog.categories {
            rows += "<tr><td><a href=\"\(resolve("/category/\(category.id)"))\"><b>\(esc(category.title))</b></a></td><td>\(esc(category.description))</td></tr>\n"
        }
        let bodyTable = rows.isEmpty
            ? "<p>Здесь пока пусто.</p>\n"
            : "<table>\n<tr><th>Раздел</th><th>Описание</th></tr>\n\(rows)</table>\n"

        let html = fullHTML(
            body: "\(nav)\(bodyTable)",
            title: site.title
        )
        return .page(SitePage(url: resolve("/"), title: site.title, html: html))
    }

    private func categoryPage(_ categoryID: String) -> SiteResponse {
        guard let category = catalog.categories.first(where: { $0.id == categoryID }) else {
            return .failure("404: /category/\(categoryID)")
        }
        var rows = ""
        for file in category.files {
            let downloaded = state.downloadCounts[file.id] ?? 0
            let countText = downloaded > 0 ? " — скачан: \(downloaded)" : ""
            rows += "<tr><td>\(esc(file.name))</td><td>\(FileSizeFormatter.format(file.sizeBytes))</td><td>\(esc(file.description))\(countText)</td><td><a href=\"\(resolve("/download/\(file.id)"))\">Скачать</a></td></tr>\n"
        }
        let body = "<h2>\(esc(category.title))</h2>\n<p>\(esc(category.description))</p>\n<table>\n<tr><th>Файл</th><th>Размер</th><th>Описание</th><th>Скачать</th></tr>\n\(rows)</table>\n"
        return .page(SitePage(
            url: resolve("/category/\(categoryID)"),
            title: category.title,
            html: fullHTML(body: body, title: catalog.site.title)
        ))
    }

    private func downloadResponse(_ fileID: String) -> SiteResponse {
        guard let (category, file) = catalog.file(withId: fileID) else {
            return .failure("404: /download/\(fileID)")
        }
        state.downloadCounts[fileID, default: 0] += 1
        let download = SiteDownload(
            id: file.id,
            fileName: file.name,
            sizeBytes: file.sizeBytes,
            sourceURL: resolve("/download/\(file.id)"),
            hasVirus: file.hasVirus,
            category: category.id,
            description: file.description
        )
        return .download(download)
    }

    // MARK: - HTML shell

    private func fullHTML(body: String, title: String) -> String {
        let site = catalog.site
        let navigation: String
        if site.navLabel.isEmpty {
            navigation = ""
        } else {
            let links = catalog.categories
                .map { "<a href=\"\(resolve("/category/\($0.id)"))\">\(esc($0.title))</a>" }
                .joined(separator: " · ")
            navigation = links.isEmpty
                ? ""
                : "<p class=\"nav\"><b>\(esc(site.navLabel)):</b> \(links)</p>\n"
        }
        return """
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(esc(title))</title>
        <style>
        body { font-family: Verdana, Arial, sans-serif; font-size: 11px;
               background: #c0c0c0; color: #000000; margin: 12px; }
        a { color: #0000ee; }
        a:visited { color: #551a8b; }
        .banner { background: #000080; color: #ffffff; padding: 6px 8px;
                  font-size: 16px; font-weight: bold; letter-spacing: 1px; }
        .tagline { font-style: italic; color: #333333; }
        .warning { color: #cc0000; font-weight: bold; }
        .nav { margin: 10px 0; }
        .nav a { margin-right: 8px; }
        table { border-collapse: collapse; background: #ffffff;
                margin-top: 8px; }
        td, th { border: 1px solid #7f7f7f; padding: 3px 8px;
                 font-size: 11px; text-align: left; }
        th { background: #d4d0c8; }
        .footer { color: #666666; margin-top: 14px; font-size: 10px; }
        </style>
        </head>
        <body>
        <div class="banner"><a href="\(resolve("/"))">\(esc(site.title))</a></div>
        <p class="tagline">\(esc(site.tagline))</p>
        <p class="warning">\(esc(site.warning))</p>
        \(navigation)
        \(body)
        <p class="footer">\(esc(site.footer))</p>
        </body>
        </html>
        """
    }

    private func resolve(_ path: String) -> URL {
        URL(string: "http://\(Self.host)\(path)")!
    }

    private func esc(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}