import Foundation

enum CurationPhase: Equatable {
    case idle
    case resolving
    case confirming(alternativeYear: Int)
    case downloadingPage
    case downloadingAssets(completed: Int, total: Int)
    case done
    case failed(String)
}

@MainActor
final class CurationManager: ObservableObject {
    @Published var phase: CurationPhase = .idle
    @Published private(set) var lastAddedEntry: SiteEntry?

    var activity: String {
        switch phase {
        case .idle: ""
        case .resolving: "Ищем снепшот…"
        case .confirming(let year): "Для \(year) снепшот не найден."
        case .downloadingPage: "Загружаем страницу…"
        case .downloadingAssets(let completed, let total):
            total > 0 ? "Скачиваем изображения (\(completed) из \(total))…" : "Скачиваем изображения…"
        case .done: "Готово."
        case .failed(let reason): reason
        }
    }

    var isBusy: Bool {
        switch phase {
        case .idle, .done: false
        default: true
        }
    }

    private struct PendingDownload {
        let url: String
        let displayDomain: String
        var timestamp: String
        let title: String
        let slug: String
        var year: Int
        let catalog: SiteCatalog
    }

    private var pendingDownload: PendingDownload?

    private struct AssetSpec {
        let url: URL
        let localName: String
    }

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/4.0 (compatible; RetroSurf 1.0; Macintosh)"
        ]
        return URLSession(configuration: configuration)
    }()

    func start(rawURL: String, year: Int, title: String, catalog: SiteCatalog, existingSlugs: Set<String>) {
        let url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayDomain = SiteCatalog.normalizedDomain(url)
        let slug = Self.generateSlug(from: title, existing: existingSlugs)

        phase = .resolving

        let pending = PendingDownload(
            url: url,
            displayDomain: displayDomain,
            timestamp: "",
            title: title,
            slug: slug,
            year: year,
            catalog: catalog
        )
        pendingDownload = pending

        Task {
            await resolve(target: pending)
        }
    }

    func confirmAlternative() {
        guard var pending = pendingDownload,
              let alternativeTimestamp = tryAlternativeTimestamp else { return }
        pending.timestamp = alternativeTimestamp
        pendingDownload = pending
        tryAlternativeTimestamp = nil
        Task {
            await download(pending)
        }
    }

    func cancel() {
        pendingDownload = nil
        tryAlternativeTimestamp = nil
        phase = .idle
    }

    private var tryAlternativeTimestamp: String?

    private func resolve(target: PendingDownload) async {
        do {
            guard let (timestamp, snapshotYear) = try await availability(url: target.url, year: target.year) else {
                phase = .failed("Снепшот не найден.")
                return
            }
            if snapshotYear != target.year {
                var pending = target
                pending.timestamp = ""
                pending.year = snapshotYear
                pendingDownload = pending
                tryAlternativeTimestamp = timestamp
                phase = .confirming(alternativeYear: snapshotYear)
                return
            }
            var pending = target
            pending.timestamp = timestamp
            pendingDownload = pending
            await download(pending)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func availability(url: String, year: Int) async throws -> (timestamp: String, year: Int)? {
        var components = URLComponents(string: "https://archive.org/wayback/available")!
        components.queryItems = [
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "timestamp", value: "\(year)0101")
        ]
        guard let apiURL = components.url else { throw CurationError.invalidURL }

        let (data, response) = try await session.data(from: apiURL)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw CurationError.server(responseCode: http.statusCode)
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let snapshots = json["archived_snapshots"] as? [String: Any],
            let closest = snapshots["closest"] as? [String: Any],
            let available = closest["available"] as? Bool, available,
            let timestamp = closest["timestamp"] as? String, !timestamp.isEmpty
        else {
            return nil
        }
        let snapshotYear = Int(timestamp.prefix(4))
        return (timestamp, snapshotYear ?? year)
    }

    private func download(_ pending: PendingDownload) async {
        guard let downloadURL = cleanSnapshotURL(url: pending.url, timestamp: pending.timestamp) else {
            phase = .failed("Не удалось сформировать адрес снепшота.")
            return
        }
        let pageBaseURL = URL(string: pending.url.hasPrefix("http") ? pending.url : "http://" + pending.url)

        phase = .downloadingPage
        do {
            let html = try await fetchText(from: downloadURL)
            let processed = processAssets(html: html, pageBaseURL: pageBaseURL)
            let rewrittenHTML = normalizeCharset(processed.html)
            let directory = SiteCatalog.curatedSitesURL.appendingPathComponent(pending.slug, isDirectory: true)
            let assetsDirectory = directory.appendingPathComponent("assets", isDirectory: true)
            try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)

            try rewrittenHTML.write(to: directory.appendingPathComponent("page.html"), atomically: true, encoding: .utf8)

            let total = processed.assets.count
            phase = .downloadingAssets(completed: 0, total: total)
            for (index, asset) in processed.assets.enumerated() {
                let localURL = assetsDirectory.appendingPathComponent(asset.localName)
                if let data = try? await fetchData(from: asset.url), !data.isEmpty {
                    try? data.write(to: localURL, options: .atomic)
                }
                phase = .downloadingAssets(completed: index + 1, total: total)
            }

            let meta = SiteMeta(
                displayDomain: pending.displayDomain,
                title: pending.title,
                shortDescription: nil,
                category: nil,
                keywords: nil,
                requiredTier: nil,
                interactiveExperienceID: nil
            )
            try writeMeta(meta, to: directory)
            pending.catalog.loadAll()
            lastAddedEntry = pending.catalog.entry(id: pending.slug)
            phase = .done
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func writeMeta(_ meta: SiteMeta, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(meta)
        try data.write(to: directory.appendingPathComponent("meta.json"), options: .atomic)
    }

    private func cleanSnapshotURL(url: String, timestamp: String) -> URL? {
        let cdn = timestamp.hasSuffix("id_") ? timestamp : timestamp + "id_"
        let target = url.hasPrefix("http") ? url : "http://" + url
        return URL(string: "https://web.archive.org/web/\(cdn)/\(target)")
    }

    private func fetchText(from url: URL) async throws -> String {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw CurationError.server(responseCode: http.statusCode)
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .windowsCP1251) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        throw CurationError.unreadablePage
    }

    private func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw CurationError.server(responseCode: http.statusCode)
        }
        return data
    }

    private func processAssets(html: String, pageBaseURL: URL?) -> (html: String, assets: [AssetSpec]) {
        let pattern = #"(?:src|href)\s*=\s*"([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (html, [])
        }
        let ns = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))

        var rewritten = html
        var map: [String: String] = [:]
        var usedNames: Set<String> = []
        var assets: [AssetSpec] = []

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let valueRange = match.range(at: 1)
            let originalValue = ns.substring(with: valueRange)
            guard let absoluteURL = assetAbsoluteURL(originalValue, base: pageBaseURL) else { continue }
            guard isAssetURL(absoluteURL) else { continue }

            let key = absoluteURL.absoluteString
            if map[key] == nil {
                let localName = Self.uniqueAssetName(for: absoluteURL, used: &usedNames)
                map[key] = localName
                assets.append(AssetSpec(url: absoluteURL, localName: localName))
            }
            if let localName = map[key], let oldRange = rewritten.range(of: originalValue) {
                rewritten = rewritten.replacingCharacters(in: oldRange, with: "assets/\(localName)")
            }
        }
        return (rewritten, assets)
    }

    private func assetAbsoluteURL(_ value: String, base: URL?) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cleaned = stripWaybackPrefix(trimmed)
        let prefixed: String
        if cleaned.hasPrefix("//") {
            prefixed = "https:" + cleaned
        } else if cleaned.hasPrefix("data:") || cleaned.hasPrefix("javascript:") || cleaned.hasPrefix("mailto:") || cleaned.hasPrefix("#") {
            return nil
        } else {
            prefixed = cleaned
        }
        guard let url = URL(string: prefixed, relativeTo: base) else { return nil }
        guard let scheme = url.scheme, ["http", "https"].contains(scheme) else { return nil }
        return url.absoluteURL
    }

    private func stripWaybackPrefix(_ value: String) -> String {
        guard let range = value.range(of: "web.archive.org/web/") else { return value }
        let inner = value[range.upperBound...]
        guard let slashIndex = inner.firstIndex(of: "/") else { return value }
        let tail = String(inner[inner.index(after: slashIndex)...])
        if tail.hasPrefix("http://") || tail.hasPrefix("https://") {
            return tail
        }
        return "http://" + tail
    }

    private func isAssetURL(_ url: URL) -> Bool {
        let assetExtensions: Set<String> = [
            "png", "jpg", "jpeg", "gif", "bmp", "webp", "svg", "ico", "css"
        ]
        guard let ext = url.pathExtension.lowercased().split(separator: "?").first.map(String.init) else {
            return false
        }
        return assetExtensions.contains(ext)
    }

    private func normalizeCharset(_ html: String) -> String {
        let legacyCharsets = "windows-1251|windows-1252|iso-8859-1|koi8-r|us-ascii"
        let pattern = "charset\\s*=\\s*[\"']?\\s*(?:\(legacyCharsets))\\s*[\"']?"
        return html.replacingOccurrences(of: pattern, with: "charset=utf-8", options: .regularExpression)
    }

    static func generateSlug(from title: String, existing: Set<String>) -> String {
        var base = makeSlugBase(title)
        if base.isEmpty {
            base = "site"
        }
        var slug = base
        var counter = 2
        while existing.contains(slug) {
            slug = "\(base)-\(counter)"
            counter += 1
        }
        return slug
    }

    private static func makeSlugBase(_ input: String) -> String {
        var result = ""
        for char in input.lowercased() {
            if let latin = transliteration[char] {
                result += latin
            } else if char.isASCII && (char.isLetter || char.isNumber) {
                result.append(char)
            } else {
                result.append("-")
            }
        }
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }
        while result.hasPrefix("-") {
            result.removeFirst()
        }
        while result.hasSuffix("-") {
            result.removeLast()
        }
        return result
    }

    private static func uniqueAssetName(for url: URL, used: inout Set<String>) -> String {
        let raw = url.lastPathComponent
        let stem = raw.isEmpty ? "asset" : raw
        var name = stem
        var counter = 2
        while used.contains(name) {
            name = "\(counter)-\(stem)"
            counter += 1
        }
        used.insert(name)
        return name
    }

    private static let transliteration: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e",
        "ж": "zh", "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m",
        "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u",
        "ф": "f", "х": "h", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sch",
        "ъ": "-", "ы": "y", "ь": "-", "э": "e", "ю": "yu", "я": "ya"
    ]
}

enum CurationError: LocalizedError {
    case invalidURL
    case server(responseCode: Int)
    case unreadablePage

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Некорректный адрес страницы."
        case .server(let code):
            return "Сервер ответил кодом \(code)."
        case .unreadablePage:
            return "Не удалось прочитать страницу (кодировка не распознана)."
        }
    }
}