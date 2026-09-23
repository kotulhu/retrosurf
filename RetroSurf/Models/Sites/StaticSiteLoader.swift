import Foundation

/// Загружает «живые» статичные сайты из Resources/sites/<slug>/index.html.
/// Такой сайт регистрируется в SiteRegistry как StaticSite и обслуживается
/// напрямую. Сайты каталога без index.html (обслуживаются через
/// SiteCatalog.page(for:) и page.html) не трогаются.
@MainActor
enum StaticSiteLoader {
    /// Сканирует подкаталоги Resources/sites, создаёт StaticSite для каждого
    /// приложения с index.html и регистрирует его, если живой сайт с таким
    /// хостом ещё не занят. Возвращает созданные сайты.
    static func loadFromBundle(registerTo registry: SiteRegistry) -> [StaticSite] {
        var created: [StaticSite] = []
        guard let bundleSites = Bundle.main.resourceURL?.appendingPathComponent("sites") else {
            return created
        }
        let fileManager = FileManager.default
        guard let slugs = try? fileManager.contentsOfDirectory(atPath: bundleSites.path) else {
            return created
        }
        for slug in slugs.sorted() {
            let directory = bundleSites.appendingPathComponent(slug, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("index.html")),
                  let html = String(data: data, encoding: .utf8) else { continue }
            let meta = try? JSONDecoder().decode(
                SiteMeta.self,
                from: Data(contentsOf: directory.appendingPathComponent("meta.json"))
            )
            let host = meta?.displayDomain ?? slug
            guard registry.site(forHost: host) == nil else { continue }
            let site = StaticSite(
                host: host,
                displayName: meta?.title ?? SiteCatalog.defaultTitle(from: slug),
                html: html
            )
            registry.register(site)
            created.append(site)
            print("[StaticSiteLoader] загружен \(host)")
        }
        return created
    }
}