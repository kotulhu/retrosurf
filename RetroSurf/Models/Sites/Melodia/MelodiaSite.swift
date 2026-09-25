import Foundation

/// Мелодия — музыкальный архив. Демонстрирует лёгкий дизайн: белый фон,
/// чёрный текст, синие подчёркнутые ссылки. Контент целиком из catalog.json
/// + генерируемых bulk-чанков; в самой мелодии нет ни одного вируса.
@MainActor
final class MelodiaSite: BaseInteractiveSite<FilesState> {
    static let host = "melodia.su"

    private static let pageSize = 30

    let catalog: FilesCatalog
    let bulk: [String: [FilesFile]]

    init(catalog: FilesCatalog, bulkLoader: FilesBulkLoader) {
        self.catalog = catalog
        self.bulk = bulkLoader.entriesByCategory
        super.init(
            descriptor: SiteDescriptor(
                id: "melodia",
                host: Self.host,
                displayName: "Мелодия",
                iconSystemName: "music.note"
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
            return handleGet(url, form: [:])
        case .submit(let url, let form):
            // GET-формы пагинации и поиска приходят сюда; page/q лежат в form.
            return handleGet(url, form: form)
        case .invoke(let action, _):
            return .failure("404: \(action)")
        case .composeAttach, .composeRemoveAttachment:
            return .failure("404")
        }
    }

    // MARK: - Routing

    private func handleGet(_ url: URL, form: [String: String]) -> SiteResponse {
        guard let host = url.host?.lowercased(), host == Self.host else {
            return .failure("Host not found: \(url.host ?? url.absoluteString)")
        }
        let path = url.path.isEmpty ? "/" : url.path
        if path == "/" { return indexPage() }
        if path.hasPrefix("/category/") {
            return categoryPage(String(path.dropFirst("/category/".count)),
                                form: form, url: url)
        }
        if path.hasPrefix("/download/") {
            return downloadResponse(String(path.dropFirst("/download/".count)))
        }
        return .failure("404: \(path)")
    }

    // MARK: - Entries

    /// Featured tracks first (written catalog entries), generated bulk appended.
    private func entries(for category: FilesCategory) -> [FilesFile] {
        var combined = category.files
        combined.append(contentsOf: bulk[category.id] ?? [])
        return combined
    }

    // MARK: - Pages

    private func indexPage() -> SiteResponse {
        let site = catalog.site
        let nav = Self.navHTML(resolve("/"), label: site.navLabel.isEmpty ? "Жанры" : site.navLabel)

        var genres = ""
        if !catalog.categories.isEmpty {
            let rows = catalog.categories.map { category in
                "<tr><td><a href=\"\(resolve("/category/\(category.id)"))\"><b>\(esc(category.title))</b></a></td>"
                    + "<td>\(esc(category.description))</td></tr>\n"
            }.joined()
            genres = "<h2 id=\"genres\">\(esc(site.navLabel))</h2>\n"
                + "<table>\n<tr><th>Жанр</th><th>Описание</th></tr>\n\(rows)</table>\n"
        }

        let about = "<p id=\"about\"><b>О сайте.</b> \(esc(site.warning)) \(esc(site.tagline))</p>\n"

        let search: String
        if let first = catalog.categories.first {
            search = "<div id=\"search\">\n\(MelodiaTemplates.searchBox(action: resolve("/category/\(first.id)"), query: ""))</div>\n"
        } else {
            search = ""
        }

        let body = "\(genres)\(about)\(search)"
        return .page(SitePage(
            url: resolve("/"),
            title: site.title,
            html: MelodiaTemplates.fullHTML(title: site.title, tagline: site.tagline,
                                            warning: site.warning, nav: nav,
                                            footer: site.footer, body: body)
        ))
    }

    private func categoryPage(_ categoryID: String, form: [String: String], url: URL) -> SiteResponse {
        guard let category = catalog.categories.first(where: { $0.id == categoryID }) else {
            return .failure("404: /category/\(categoryID)")
        }
        let site = catalog.site

        let rawQuery = (form["q"] ?? Self.queryValue("q", from: url) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = rawQuery.lowercased()
        let rawPage = form["page"] ?? Self.queryValue("page", from: url)

        let all = entries(for: category)
        let filtered = needle.isEmpty
            ? all
            : all.filter { $0.name.lowercased().contains(needle) || $0.description.lowercased().contains(needle) }

        let totalPages = max(1, Int(ceil(Double(filtered.count) / Double(Self.pageSize))))
        var page = rawPage.flatMap(Int.init) ?? 1
        page = min(max(page, 1), totalPages)
        let start = (page - 1) * Self.pageSize
        let slice = filtered.dropFirst(start).prefix(Self.pageSize)

        var rows = ""
        for file in slice {
            let downloaded = state.downloadCounts[file.id] ?? 0
            let countText = downloaded > 0 ? " — скачан: \(downloaded)" : ""
            rows += "<tr><td>\(esc(file.name))</td><td>\(FileSizeFormatter.format(file.sizeBytes))</td>"
                + "<td>\(esc(file.description))\(countText)</td>"
                + "<td><a href=\"\(resolve("/download/\(file.id)"))\">Скачать</a></td></tr>\n"
        }

        var body = "<h2>\(esc(category.title))</h2>\n<p>\(esc(category.description))</p>\n"
            + MelodiaTemplates.searchBox(action: resolve("/category/\(categoryID)"), query: rawQuery)
        if filtered.isEmpty {
            body += "<p>Ничего не найдено.</p>\n"
        } else {
            body += "<table>\n<tr><th>Файл</th><th>Размер</th><th>Описание</th><th>Скачать</th></tr>\n\(rows)</table>\n"
            body += Self.paginationHTML(page: page, totalPages: totalPages,
                                        categoryID: categoryID, query: rawQuery)
        }

        return .page(SitePage(
            url: resolve("/category/\(categoryID)"),
            title: category.title,
            html: MelodiaTemplates.fullHTML(title: site.title, tagline: site.tagline,
                                            warning: site.warning, nav: Self.navHTML(resolve("/"), label: site.navLabel),
                                            footer: site.footer, body: body)
        ))
    }

    private func downloadResponse(_ fileID: String) -> SiteResponse {
        guard let download = self.download(forFileID: fileID) else {
            return .failure("404: /download/\(fileID)")
        }
        state.downloadCounts[fileID, default: 0] += 1
        return .download(download)
    }

    /// Rebuilds the SiteDownload for any catalog-or-bulk file — also used by
    /// the «Загрузки» panel for re-downloading a completed file.
    func download(forFileID fileID: String) -> SiteDownload? {
        for category in catalog.categories {
            if let file = entries(for: category).first(where: { $0.id == fileID }) {
                return SiteDownload(
                    id: file.id,
                    fileName: file.name,
                    sizeBytes: file.sizeBytes,
                    sourceURL: resolve("/download/\(file.id)"),
                    hasVirus: file.hasVirus,
                    category: category.id,
                    description: file.description
                )
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func navHTML(_ home: URL, label: String) -> String {
        "<p class=\"nav\"><a href=\"\(home.absoluteString)\">Главная</a> · "
            + "<a href=\"\(home.absoluteString)#genres\">\(label)</a> · "
            + "<a href=\"\(home.absoluteString)#search\">Поиск</a> · "
            + "<a href=\"\(home.absoluteString)#about\">О сайте</a></p>\n"
    }

    private static func paginationHTML(page: Int, totalPages: Int,
                                       categoryID: String, query: String) -> String {
        guard totalPages > 1 else { return "" }
        var parts: [String] = []
        for p in 1...totalPages {
            if p == page {
                parts.append(String(p))
            } else {
                var href = "/category/\(categoryID)?page=\(p)"
                if !query.isEmpty {
                    href += "&q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"
                }
                parts.append("<a href=\"\(href)\">\(p)</a>")
            }
        }
        return "<p class=\"pager\">Страницы: \(parts.joined(separator: " · "))</p>\n"
    }

    static func queryValue(_ name: String, from url: URL) -> String? {
        guard let query = url.query else { return nil }
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0].removingPercentEncoding == name {
                return String(parts[1]).removingPercentEncoding
            }
            if parts.count == 1, parts[0].removingPercentEncoding == name {
                return ""
            }
        }
        return nil
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