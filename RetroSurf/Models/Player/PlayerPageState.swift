import Combine
import Foundation

/// Состояние опубликованной личной странички игрока. Заполняется установщиком
/// один раз; повторная публикация той же странички ничего не меняет.
@MainActor
final class PlayerPageState: ObservableObject {
    @Published private(set) var isPublished = false
    @Published private(set) var username: String?
    @Published private(set) var pageURL: URL?

    /// Публикует страничку. Идемпотентно по (username, pageURL).
    func publish(username: String, pageURL: URL) {
        if isPublished, self.username == username, self.pageURL == pageURL {
            return
        }
        isPublished = true
        self.username = username
        self.pageURL = pageURL
    }
}