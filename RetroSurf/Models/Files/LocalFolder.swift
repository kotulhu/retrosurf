import Foundation

/// Локальные папки пользовательских файлов. Файлы в этих папках живут
/// только "в данных" — никакой записи на реальный диск не происходит.
enum LocalFolder: String, Sendable, CaseIterable, Identifiable, Codable {
    /// Загрузки — сюда складываются завершённые загрузки с files.su.
    case downloads
    /// Мои документы — пользовательская папка.
    case documents
    /// Картинки — пользовательская папка для изображений.
    case pictures

    var id: String { rawValue }

    /// Реальные узлы в FileStore имеют вид "local:<имя папки>".
    /// Загрузки раньше жили в legacy-узле "downloads" — он читается
    /// отдельно как тот же .downloads.
    var ownerNode: String { "local:\(displayName)" }

    /// Заголовок, который показывается в интерфейсе.
    var displayName: String {
        switch self {
        case .downloads: return "Загрузки"
        case .documents: return "Мои документы"
        case .pictures: return "Картинки"
        }
    }

    /// Обратная раскладка узла в папку. Понимает и legacy-узел "downloads",
    /// и новые узлы "local:<имя>", и (на всякий случай) "local:<rawValue>".
    static func folder(forOwnerNode node: String?) -> LocalFolder? {
        guard let node else { return nil }
        for folder in Self.allCases where folder.ownerNode == node {
            return folder
        }
        switch node {
        case "downloads": return .downloads
        case "local:downloads": return .downloads
        case "local:documents": return .documents
        case "local:pictures": return .pictures
        default: return nil
        }
    }

    /// Все узлы (включая legacy), которые соответствуют этой папке.
    var matchingNodes: [String] {
        switch self {
        case .downloads: return [ownerNode, "downloads", "local:downloads"]
        case .documents: return [ownerNode, "local:documents"]
        case .pictures: return [ownerNode, "local:pictures"]
        }
    }
}