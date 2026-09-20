import Foundation

@MainActor
enum AggregatorPageBuilder {
    static let portalName = "Ориентир.ру"
    static let portalDomain = "orientir.ru"

    private static let portalURL = "retrosurf://orientir.ru"

    static func homeHTML(catalog: SiteCatalog, progress: GameProgress, quests: QuestManager) -> String {
        let total = catalog.entries.count
        let visited = progress.visitedCount
        let completedBySite: [String: Bool] = Dictionary(uniqueKeysWithValues: catalog.entries.map { ($0.id, quests.hasCompletedQuestFor(siteID: $0.id)) })
        let counterValue = 124_031 + visited * 7

        var h: [String] = []
        h.append("""
        <!DOCTYPE HTML>
        <html lang="ru">
        <head>
        <meta charset="utf-8">
        <title>\(portalName) — каталог российского Интернета</title>
        <style>
        body { background-color:#f3efd8; color:#1a1a1a; font-family:"Times New Roman",Georgia,serif; margin:0; padding:0; -webkit-font-smoothing:none; }
        table { border-collapse:collapse; }
        a { color:#003399; }
        a:visited { color:#660099; }
        .logo { font-size:54px; font-weight:bold; color:#8b1a1a; }
        .logo sub { font-size:20px; color:#555555; }
        .tagline { font-size:15px; color:#444444; }
        .navbar td { background-color:#cdbf86; border:1px solid #7a6a2a; padding:4px 9px; font-size:13px; }
        .navlink { color:#5a3d00; font-weight:bold; }
        .top td { background-color:#ffffff; font-size:13px; }
        .catwad { background-color:#c96f1d; color:#ffffff; font-weight:bold; font-size:13px; }
        .entry td { border:1px solid #e2d9b0; padding:5px 8px; background-color:#ffffff; }
        .domain { color:#777777; font-size:12px; }
        .locked td { border:1px solid #e2d9b0; padding:5px 8px; background-color:#eae6d4; }
        .locked a, .locked .domain { color:#9a9a9a; cursor:default; }
        .locknote { color:#b05000; font-size:12px; white-space:nowrap; }
        .fresh { color:#cc0000; font-weight:bold; font-size:13px; }
        .lockicon { font-size:12px; }
        .stat td { padding:5px 12px; font-size:13px; background-color:#d5e6f2; border:1px solid #6a94b5; }
        .counter { font-family:"Courier New",monospace; font-size:15px; color:#003366; font-weight:bold; }
        .banner { width:88px; height:31px; text-align:center; border:1px solid #000000; font-family:Arial,Helvetica,sans-serif; font-size:9px; font-weight:bold; line-height:1.1; }
        .founder { font-size:12px; color:#555555; }
        </style>
        </head>
        <body>
        <center>
        <span class="logo">Ориентир<sub>.ру</sub></span>
        <br>
        <span class="tagline">Каталог сайтов российского Интернета — стартовая страница вебмастера с 1999 года</span>
        <br><br>
        <marquee scrollamount="5" width="720" style="font-size:12px; color:#8b1a1a;">оптимизировано для 800×600 · работает в Netscape 3.0 и MSIE 4.0 · файл грузится 3 минуты на скорости 14.4 kbps · вебмастерам: бесплатная раскрутка</marquee>
        <br>
        """)

        h.append("<table class=\"navbar\" width=\"720\" cellspacing=\"4\" cellpadding=\"2\"><tr>")
        for category in SiteCategory.allCases {
            h.append("<td align=\"center\"><a class=\"navlink\" href=\"#cat-\(category.rawValue)\">\(escape(category.title))</a></td>")
        }
        h.append("</tr></table><br>")

        let top = Array(catalog.entries.prefix(3))
        h.append("<table width=\"720\" class=\"top\" cellpadding=\"3\" cellspacing=\"2\"><tr><th colspan=\"3\" bgcolor=\"#5a6a2a\" style=\"color:#ffffff; font-size:14px;\">ТОП-3 сайтов недели</th></tr>")
        for (index, entry) in top.enumerated() {
            let hits = 8_700 - index * 1_030 + progress.visitedCount * 5
            h.append("<tr><td width=\"40\" align=\"center\">\(index + 1).</td><td>\(escape(entry.title))</td><td align=\"right\">▲ \(hits)</td></tr>")
        }
        h.append("</table><br>")

        for category in SiteCategory.allCases {
            let items = catalog.entries(in: category)
            if items.isEmpty { continue }
            h.append("<a name=\"cat-\(category.rawValue)\"></a>")
            h.append("<table width=\"720\" cellpadding=\"2\" cellspacing=\"2\"><tr><td class=\"catwad\" width=\"30\" align=\"center\">\(escape(category.icon))</td><td align=\"left\" style=\"font-size:17px; font-weight:bold; color:#3a3a00;\">\(escape(category.title)) <small style=\"font-weight:normal; color:#777777;\">(\(items.count))</small></td></tr></table>")
            h.append("<table width=\"720\" cellpadding=\"0\" cellspacing=\"2\">")
            for entry in items {
                let questDone = completedBySite[entry.id] == true
                let titleText = questDone
                    ? "\(escape(entry.title)) <small style=\"color:#1a6600;\">(пройдено)</small>"
                    : escape(entry.title)
                if progress.isUnlocked(entry) {
                    let fresh = progress.isVisited(entry.id) ? "&nbsp;" : "<span class=\"fresh\">🆕</span>"
                    h.append("<tr class=\"entry\"><td width=\"30\" align=\"center\">\(fresh)</td><td><a href=\"retrosurf://\(entry.displayDomain)\"><b>\(titleText)</b></a><span class=\"domain\"> — \(escape(entry.displayDomain))</span><br><small>\(escape(entry.shortDescription))</small></td></tr>")
                } else {
                    h.append("<tr class=\"locked\"><td width=\"30\" align=\"center\" class=\"lockicon\">🔒</td><td><b>\(titleText)</b><span class=\"domain\"> — \(escape(entry.displayDomain))</span><br><small>\(escape(entry.shortDescription))</small><br><span class=\"locknote\">Доступно на скорости \(escape(entry.requiredTier.fullLabel))</span></td></tr>")
                }
            }
            h.append("</table><br>")
        }

        h.append("<table class=\"stat\" width=\"720\" cellpadding=\"0\" cellspacing=\"2\"><tr><th colspan=\"2\" bgcolor=\"#4a7ba3\" style=\"color:#ffffff; font-size:14px; padding:3px;\">Статистика сайта</th></tr>")
        h.append("<tr><td width=\"260\">Посещено сайтов:</td><td class=\"counter\">\(visited) из \(total)</td></tr>")
        h.append("<tr><td>Текущая скорость:</td><td class=\"counter\">\(escape(progress.currentTier.fullLabel))</td></tr>")
        h.append("<tr><td>Счётчик посещений:</td><td class=\"counter\">\(String(format: "%08d", counterValue))</td></tr>")
        h.append("<tr><td>Файлов подгружено:</td><td class=\"counter\">\(counterValue / 3)</td></tr>")
        h.append("</table><br>")

        let slogans = [
            "БЕСПЛАТНЫЙ ХОСТИНГ!", "СДЕЛАНО НА ЧИСТОМ HTML", "САЙТ НЕДЕЛИ", "ICQ: 312-414-558", "МОДЕМ?! ЭТО НА 56k!",
            "РЕКЛАМА ЗДЕСЬ", "УСКОРИСЬ! УЖЕ 28.8", "MSIE 4.0 РЕКОМЕНДУЕТ", "НОВЫЙ ЧАТ!", "ПОГОДА В РУНЕТЕ"
        ]
        let palettes: [(bg: String, fg: String)] = [
            ("#cc0000", "#ffffff"), ("#ffcc00", "#333300"), ("#0099cc", "#ffffff"),
            ("#ffffff", "#660066"), ("#ff6600", "#ffffff"), ("#ffffff", "#006600"),
            ("#339933", "#ffffff"), ("#000000", "#ffff00"), ("#ffffff", "#cc0000"), ("#99ccff", "#000000")
        ]
        h.append("<table width=\"720\" cellpadding=\"2\" cellspacing=\"2\">")
        for rowStart in stride(from: 0, to: slogans.count, by: 5) {
            h.append("<tr>")
            let rowEnd = min(rowStart + 5, slogans.count)
            for i in rowStart..<rowEnd {
                let palette = palettes[i % palettes.count]
                h.append("<td class=\"banner\" bgcolor=\"\(palette.bg)\" style=\"color:\(palette.fg)\">\(escape(slogans[i]))</td>")
            }
            h.append("</tr>")
        }
        h.append("</table><br>")

        h.append("<hr width=\"720\" color=\"#8b1a1a\">")
        h.append("<small class=\"founder\">(c) 1999 \(portalName) · вебмастеру: webmaster@\(portalDomain) · без JavaScript — только таблицы</small>")
        h.append("</center></body></html>")

        return h.joined(separator: "\n")
    }

    static func placeholderHTML(for entry: SiteEntry) -> String {
        """
        <!DOCTYPE HTML>
        <html lang="ru">
        <head>
        <meta charset="utf-8">
        <title>\(escape(entry.title))</title>
        <style>
        body { background-color:#fdedd0; font-family:"Times New Roman",Georgia,serif; color:#2a2015; -webkit-font-smoothing:none; }
        .big { font-size:30px; font-weight:bold; color:#5c3317; }
        table { border-collapse:collapse; }
        </style>
        </head>
        <body>
        <center>
        <h1 class="big">\(escape(entry.title))</h1>
        <table border="1" cellpadding="10" width="560" bgcolor="#fff8e7">
        <tr><td align="center"><b>www.\(escape(entry.displayDomain))</b></td></tr>
        <tr><td align="center">\(escape(entry.shortDescription))</td></tr>
        <tr><td align="center"><small>Здесь скоро появится настоящее содержимое сайта.</small><br><small>Раздел «\(escape(entry.category.title))» каталога «Ориентир.ру» · загрузка: \(escape(entry.requiredTier.fullLabel))</small></td></tr>
        <tr><td align="center"><a href="\(portalURL)">← Вернуться на Ориентир.ру</a></td></tr>
        </table>
        <small>(пока без содержимого — идёт загрузка по модему…)</small>
        </center>
        </body>
        </html>
        """
    }

    static func notFoundHTML(domain: String) -> String {
        let shown = domain.isEmpty ? AggregatorPageBuilder.portalDomain : domain
        return """
        <!DOCTYPE HTML>
        <html lang="ru">
        <head>
        <meta charset="utf-8">
        <title>Сайт не найден</title>
        <style>
        body { background-color:#e0e0e0; font-family:"Times New Roman",Georgia,serif; -webkit-font-smoothing:none; }
        </style>
        </head>
        <body>
        <center>
        <h1 style="color:#660000;">Ошибка 404</h1>
        <p>Сайт <b>\(escape(shown))</b> не найден в каталоге «Ориентир.ру».</p>
        <p>Проверьте адрес или вернитесь на <a href="\(portalURL)">стартовую страницу</a>.</p>
        <hr width="400" color="#660000">
        <small>(c) 1999 Ориентир.ру</small>
        </center>
        </body>
        </html>
        """
    }

    private static func escape(_ text: String) -> String {
        var s = text
        for (from, to) in [
            ("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"), ("\"", "&quot;"), ("'", "&#39;")
        ] {
            s = s.replacingOccurrences(of: from, with: to)
        }
        return s
    }
}