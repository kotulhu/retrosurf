import Foundation

/// Одна атмосферная рассылка из каталога.
struct AmbientTemplate: Codable, Sendable, Identifiable {
    let id: String
    let subject: String
    let bodyHTML: String
    let weight: Int
}

/// Каталог атмосферных рассылок (спам-шаблоны) из
/// Resources/Mail/{name}.json. На пустой/битый каталог никогда не падает.
struct AmbientCatalog: Codable, Sendable {
    let templates: [AmbientTemplate]

    init(templates: [AmbientTemplate] = []) {
        self.templates = templates
    }

    /// Загружает Resources/Mail/{name}.json (копируется в корень Contents/Resources,
    /// как и остальные ресурсы проекта). При ошибке загрузки или декодирования
    /// возвращает пустой каталог и печатает причину.
    static func loadFromBundle(named name: String = "ambient") -> AmbientCatalog {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            print("[AmbientCatalog] not found: Resources/Mail/\(name).json")
            return AmbientCatalog()
        }
        do {
            let data = try Data(contentsOf: url)
            let catalog = try JSONDecoder().decode(AmbientCatalog.self, from: data)
            print("[AmbientCatalog] loaded \(catalog.templates.count) template(s) from \(url.path)")
            return catalog
        } catch {
            print("[AmbientCatalog] decoding error: \(error)")
            return AmbientCatalog()
        }
    }
}