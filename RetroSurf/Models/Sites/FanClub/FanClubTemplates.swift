import Foundation

/// HTML-шаблоны фан-клуба «Полнолуние». Ночная палитра (тёмно-синий фон,
/// бледно-голубой текст), баннер со звёздами, навигация по разделам.
/// Единственный источник контента — FanClubContent.
enum FanClubTemplates {
    static let baseURL = "http://polnolunie-fanclub.su"

    private struct NavItem {
        let key: String
        let label: String
        let path: String
    }

    private static let navItems: [NavItem] = [
        NavItem(key: "about", label: "О группе", path: "/about"),
        NavItem(key: "members", label: "Состав", path: "/members"),
        NavItem(key: "discography", label: "Дискография", path: "/discography"),
        NavItem(key: "songs", label: "Песни", path: "/songs"),
        NavItem(key: "mp3", label: "MP3", path: "/mp3"),
        NavItem(key: "guestbook", label: "Гостевая", path: "/guestbook"),
        NavItem(key: "links", label: "Ссылки", path: "/links"),
    ]

    // MARK: - Shell

    static func fullHTML(
        site: FanClubContent.SiteMeta,
        title: String,
        body: String,
        active: String?
    ) -> String {
        let links = navItems.map { item in
            let css = item.key == active ? " class=\"active\"" : ""
            return "<a\(css) href=\"\(baseURL)\(item.path)\">\(escapeHTML(item.label))</a>"
        }.joined(separator: " · ")

        let navHTML = site.navLabel.isEmpty
            ? ""
            : "<p class=\"nav\"><b>\(escapeHTML(site.navLabel)):</b> \(links)</p>\n"

        let warningHTML = site.warning.isEmpty
            ? ""
            : "<p class=\"warning\"><small>\(escapeHTML(site.warning))</small></p>\n"

        let footerHTML = site.footer.isEmpty
            ? ""
            : "<p class=\"footer\"><small>\(escapeHTML(site.footer))</small></p>\n"

        return """
        <!DOCTYPE HTML>
        <html lang="ru">
        <head>
        <meta charset="utf-8">
        <title>\(escapeHTML(title))</title>
        <style>
        body { background-color:#000033; color:#ccccff; font-family:Verdana,Arial,sans-serif; font-size:11px; -webkit-font-smoothing:none; }
        a { color:#6699ff; }
        a:visited { color:#8866cc; }
        a.active { color:#ffffff; font-weight:bold; }
        .banner { font-family:Verdana,Arial,sans-serif; font-size:30px; font-weight:bold; color:#ffffff; letter-spacing:4px; }
        .bannerstar { color:#ccffcc; }
        .tagline { font-size:12px; color:#99aacc; }
        .nav { font-size:11px; }
        .gotonews { font-size:12px; color:#ccccff; }
        .warning { color:#cc6666; }
        .footer { color:#667799; }
        table { border-collapse:collapse; }
        td, th { padding:4px 8px; }
        th { color:#ffffff; background-color:#1a1a4e; }
        .lyrics { font-size:12px; color:#e8e8ff; line-height:1.5; }
        .entry { background-color:#101040; border:1px solid #333366; }
        .entrytitle { font-weight:bold; color:#ffffff; }
        .entrybody { color:#ccccff; }
        .entrydate { color:#8899cc; font-size:10px; }
        input, textarea { background-color:#101040; color:#ccccff; border:1px solid #4466aa; font-family:Verdana,Arial,sans-serif; font-size:11px; }
        .msg-ok { color:#88ff88; font-weight:bold; }
        .msg-err { color:#ff8888; font-weight:bold; }
        </style>
        </head>
        <body>
        <center>
        <p class="banner"><span class="bannerstar">★</span> ПОЛНОЛУНИЕ <span class="bannerstar">★</span></p>
        <p class="tagline">\(escapeHTML(site.tagline))</p>
        <br>
        \(navHTML)
        <table width="640" cellpadding="6" cellspacing="0" border="1"><tr><td bgcolor="#0a0a38" align="center">
        \(body)
        </td></tr></table>
        <br>
        \(warningHTML)
        \(footerHTML)
        </center>
        </body>
        </html>
        """
    }

    // MARK: - Pages

    static func indexBody(site: FanClubContent.SiteMeta) -> String {
        let sections = navItems.map { item in
            "<tr><td align=\"left\"><a href=\"\(baseURL)\(item.path)\"><b>\(escapeHTML(item.label))</b></a></td></tr>"
        }.joined(separator: "\n")
        return """
        <p class="gotonews">Добро пожаловать в фан-клуб. Здесь всё, что сохранилось о группе — биография, состав, дискография, тексты песен и записи. Расходитесь по разделам:</p>
        <table>\(sections)</table>
        """
    }

    static func aboutBody(content: FanClubContent) -> String {
        let paragraphs = content.about.map { paragraph in
            "<p align=\"left\">\(escapeHTML(paragraph).replacingOccurrences(of: "\n", with: "<br>\n"))</p>"
        }.joined(separator: "\n")
        return "<h3>О группе</h3>\n\(paragraphs)"
    }

    static func membersBody(content: FanClubContent) -> String {
        guard !content.members.isEmpty else {
            return "<h3>Состав</h3>\n<p>Здесь пока пусто.</p>\n"
        }
        let rows = content.members.map { member in
            "<tr><td class=\"entry\"><b>\(escapeHTML(member.name))</b><br><small>\(escapeHTML(member.role))</small><br><span class=\"entrybody\">\(escapeHTML(member.bio))</span></td></tr>"
        }.joined(separator: "\n")
        return "<h3>Состав группы</h3>\n<table>\(rows)</table>\n"
    }

    static func discographyBody(content: FanClubContent) -> String {
        guard !content.discography.isEmpty else {
            return "<h3>Дискография</h3>\n<p>Здесь пока пусто.</p>\n"
        }
        let rows = content.discography.map { album in
            "<tr><th>\(escapeHTML(album.year))</th><td align=\"left\"><b>\(escapeHTML(album.title))</b><br>\(escapeHTML(album.description))</td></tr>"
        }.joined(separator: "\n")
        return "<h3>Дискография</h3>\n<table>\(rows)</table>\n"
    }

    static func songsBody(content: FanClubContent) -> String {
        guard !content.songs.isEmpty else {
            return "<h3>Песни</h3>\n<p>Здесь пока пусто.</p>\n"
        }
        let items = content.songs.map { song in
            "<tr><td class=\"entry\"><a href=\"\(baseURL)/song/\(song.id)\"><b>\(escapeHTML(song.title))</b></a></td></tr>"
        }.joined(separator: "\n")
        return "<h3>Песни</h3>\n<p>Нажмите на название, чтобы увидеть текст.</p>\n<table>\(items)</table>\n"
    }

    static func songBody(song: FanClubContent.Song) -> String {
        let lyrics = escapeHTML(song.lyrics).replacingOccurrences(of: "\n", with: "<br>\n")
        return """
        <h3>\(escapeHTML(song.title))</h3>
        <div align="left"><span class="lyrics">\(lyrics)</span></div>
        <p><a href="\(baseURL)/songs">← Все песни</a></p>
        """
    }

    static func mp3Body(content: FanClubContent) -> String {
        guard !content.mp3.isEmpty else {
            return "<h3>MP3</h3>\n<p>Здесь пока пусто.</p>\n"
        }
        let rows = content.mp3.map { mp3 in
            "<tr><td align=\"left\"><b>\(escapeHTML(mp3.title))</b><br><small>\(FileSizeFormatter.format(mp3.sizeBytes)) · \(escapeHTML(mp3.description))</small></td><td><a href=\"\(baseURL)/mp3/download/\(mp3.id)\">Скачать</a></td></tr>"
        }.joined(separator: "\n")
        return "<h3>MP3</h3>\n<p>Все записи — прямо с кассет. Скачивайте на здоровье!</p>\n<table>\(rows)</table>\n"
    }

    static func guestbookBody(
        content: FanClubContent,
        entries: [GuestbookEntry],
        message: String?
    ) -> String {
        var html = "<h3>Гостевая книга</h3>\n"
        if let message {
            let css = message.hasPrefix("Спасибо") ? "msg-ok" : "msg-err"
            html += "<p class=\"\(css)\">\(escapeHTML(message))</p>\n"
        }

        html += """
        <p align="left">Оставьте запись — фан-клубу будет приятно!</p>
        <form method="get" action="\(baseURL)/guestbook">
        <table>
        <tr><td align="left">Ваше имя:</td><td align="left"><input type="text" name="author" size="32"></td></tr>
        <tr><td align="left">E-mail (необязательно):</td><td align="left"><input type="text" name="email" size="32"></td></tr>
        <tr><td align="left" valign="top">Запись:</td><td align="left"><textarea name="text" rows="5" cols="46"></textarea></td></tr>
        <tr><td></td><td align="left"><input type="submit" value="Отправить в гостевую"></td></tr>
        </table>
        </form>
        <hr>
        """

        if entries.isEmpty {
            html += "<p>Записей пока нет — будьте первым!</p>\n"
        } else {
            let rows = entries.map { entry in
                let author = entry.email.isEmpty
                    ? "<b>\(escapeHTML(entry.author))</b>"
                    : "<b>\(escapeHTML(entry.author))</b> (<a href=\"mailto:\(escapeHTML(entry.email))\">\(escapeHTML(entry.email))</a>)"
                return """
                <tr class="entry"><td align="left">
                <span class="entrytitle">\(author)</span> <span class="entrydate">· \(formatted(entry.timestamp))</span>
                <br><span class="entrybody">\(escapeHTML(entry.text).replacingOccurrences(of: "\n", with: "<br>\n"))</span>
                </td></tr>
                """
            }.joined(separator: "\n")
            html += "<table>\(rows)</table>\n"
        }
        return html
    }

    static func linksBody() -> String {
        let items = [
            ("http://files.su", "Files.su", "архив файлов и программ — драйверы, музыка, картинки"),
            ("http://pochta.su", "Pochta.su", "бесплатная электронная почта Рунета"),
            ("http://homepage.su", "Homepage.su", "личные странички вебмастеров"),
            ("http://webmaster-serega.su", "Webmaster-serega.su", "советы начинающему вебмастеру"),
        ]
        let rows = items.map { url, name, desc in
            "<tr class=\"entry\"><td align=\"left\"><a href=\"\(url)\"><b>\(escapeHTML(name))</b></a><br><small>\(escapeHTML(desc))</small></td></tr>"
        }.joined(separator: "\n")
        return "<h3>Ссылки</h3>\n<p>Проверенные сайты, без которых Рунет — не Рунет.</p>\n<table>\(rows)</table>\n"
    }

    // MARK: - Helpers

    static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func formatted(_ date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.day, .month, .year, .hour, .minute], from: date)
        guard let day = components.day,
              let month = components.month,
              let year = components.year,
              let hour = components.hour,
              let minute = components.minute else {
            return ""
        }
        return String(format: "%02d.%02d.%d %02d:%02d", day, month, year, hour, minute)
    }
}