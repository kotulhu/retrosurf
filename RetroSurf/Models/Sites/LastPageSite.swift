import Foundation

/// Stateless persisted payload — the final page is purely derived from live
/// session stats, so the state is intentionally empty.
struct LastPageState: Codable, Sendable {}

/// «Последняя страница интернета» — a dark, green-on-black page showing the
/// whole session's statistics. NOT registered until the artifact threshold is
/// reached (FinalSiteInstaller handles that); before then the host is simply
/// unknown and yields a 404.
@MainActor
final class LastPageSite: BaseInteractiveSite<LastPageState> {
    static let host = "lastpage.su"

    private let stats: SessionStats
    private let progress: ProgressStore

    init(stats: SessionStats, progress: ProgressStore) {
        self.stats = stats
        self.progress = progress
        super.init(
            descriptor: SiteDescriptor(
                id: "lastpage",
                host: Self.host,
                displayName: "Последняя страница интернета",
                iconSystemName: "text.append"
            ),
            initialState: LastPageState()
        )
    }

    override func resetGameplay() {
        state = LastPageState()
    }

    override func handle(_ request: SiteRequest) async -> SiteResponse {
        switch request {
        case .open(let url):
            return handleGet(url)
        case .submit, .invoke, .composeAttach, .composeRemoveAttachment:
            return .failure("404")
        }
    }

    private func handleGet(_ url: URL) -> SiteResponse {
        let path = url.path.isEmpty ? "/" : url.path
        guard path == "/" else {
            return .failure("404: \(path)")
        }
        let html = LastPageTemplates.page(stats: stats, progress: progress)
        return .page(SitePage(url: url, title: descriptor.displayName, html: html))
    }
}

@MainActor
enum LastPageTemplates {
    static func page(stats: SessionStats, progress: ProgressStore) -> String {
        """
        <!DOCTYPE HTML>
        <html lang="ru">
        <head>
        <meta charset="utf-8">
        <title>Последняя страница интернета</title>
        <style>
        body { background-color:#000000; color:#ffffff; font-family:"Courier New",monospace; -webkit-font-smoothing:none; text-align:center; }
        a { color:#00ff00; }
        h1 { color:#00ff00; letter-spacing:2px; }
        .stat { color:#00ff00; font-size:15px; padding:4px; }
        .label { color:#777777; font-size:12px; }
        .blink { animation: blink 1.2s step-end infinite; }
        @keyframes blink { 50% { opacity:0; } }
        </style>
        </head>
        <body>
        <br><br>
        <h1>🕸 Последняя страница интернета 🕸</h1>
        <p style="color:#999999;">Вы прошли весь интернет. Дальше ничего нет.</p>
        <br>
        <p class="label">Время в сети</p>
        <p class="stat">\(stats.elapsedFormatted)</p>
        <p class="label">Передано (вверх)</p>
        <p class="stat">\(stats.formatted(stats.megabytesTransferred)) МБ</p>
        <p class="label">Скачано</p>
        <p class="stat">\(stats.formatted(stats.megabytesDownloaded)) МБ</p>
        <br>
        <p class="label">Артефакты: \(progress.points) очков</p>
        <br>
        <p class="blink" style="color:#ff0000;">— КОНЕЦ —</p>
        <br>
        <p><a href="retrosurf://orientir.su">← Вернуться на первую страницу</a></p>
        <br>
        <p style="color:#333333; font-size:11px;">© 1999 RetroSurf · вы всё посмотрели</p>
        </body>
        </html>
        """
    }
}