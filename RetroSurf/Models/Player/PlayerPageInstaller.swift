import Combine
import Foundation

/// Следит за квестовым флагом quest.webmaster.done (рассылается через
/// NotificationCenter .retroFlagSet) и устанавливает личную страничку игрока
/// на homepage.su (/p/you.html). Идемпотентно: повторная установка для того же
/// имени ничего не меняет, отсутствие homepage.su не приводит к сбою.
@MainActor
final class PlayerPageInstaller {
    static let playerPagePath = "/p/you.html"

    private let registry: SiteRegistry
    private let mailSite: MailSite
    private let state: PlayerPageState
    private var cancellables: Set<AnyCancellable> = []
    private var installedUsername: String?

    init(registry: SiteRegistry, mailSite: MailSite, state: PlayerPageState) {
        self.registry = registry
        self.mailSite = mailSite
        self.state = state
    }

    /// Подписывается на уведомления .retroFlagSet. При флаге
    /// quest.webmaster.done=true устанавливает страничку.
    func start() {
        cancellables.removeAll()
        NotificationCenter.default.publisher(for: .retroFlagSet)
            .sink { [weak self] notification in
                guard let self else { return }
                guard let key = notification.userInfo?["key"] as? String,
                      let value = notification.userInfo?["value"] as? Bool,
                      key == "quest.webmaster.done", value else { return }
                self.installNow()
            }
            .store(in: &cancellables)
    }

    /// Устанавливает страничку немедленно (для отладки или ручного запуска).
    /// Возвращает false, если страничка уже установлена для этого имени или
    /// homepage.su недоступен.
    @discardableResult
    func installNow(username: String? = nil) -> Bool {
        let resolved = username ?? mailSite.currentUsername ?? "пользователь"
        guard installedUsername != resolved else {
            print("[PlayerPageInstaller] страничка уже установлена для \(resolved)")
            return false
        }
        let html = PlayerPageBuilder.build(username: resolved)
        let pageURL = URL(string: "http://\(HomepageSite.host)\(Self.playerPagePath)")!
        guard let site = registry.site(forHost: HomepageSite.host) else {
            print("[PlayerPageInstaller] homepage.su не зарегистрирован — пропускаю")
            return false
        }
        switch site {
        case let staticSite as StaticSite:
            staticSite.addPage(path: Self.playerPagePath, html: html)
        case let homepage as HomepageSite:
            homepage.addPage(path: Self.playerPagePath, html: html)
        default:
            print("[PlayerPageInstaller] неожиданный сайт homepage.su: \(type(of: site)) — пропускаю")
            return false
        }
        installedUsername = resolved
        state.publish(username: resolved, pageURL: pageURL)
        print("[PlayerPageInstaller] личная страничка \(resolved) → \(pageURL.absoluteString)")
        return true
    }
}