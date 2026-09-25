import Foundation

/// HTML-шаблоны love.su — розовая палитра 90-х, таблица анкет на главной
/// и полная карточка профиля. Единственный источник текста — LoveContent.
enum LoveTemplates {
    static let baseURL = "http://love.su"

    private struct NavItem {
        let key: String
        let label: String
        let path: String
    }

    private static func navItems(unreadCount: Int) -> [NavItem] {
        let mailLabel = unreadCount > 0 ? "Переписка (\(unreadCount))" : "Переписка"
        return [
            NavItem(key: "index", label: "Анкеты", path: "/"),
            NavItem(key: "mail", label: mailLabel, path: "/mail"),
            NavItem(key: "about", label: "О сайте", path: "/about"),
        ]
    }

    // MARK: - Shell

    static func fullHTML(
        site: LoveContent.SiteMeta,
        title: String,
        body: String,
        active: String?,
        unreadCount: Int
    ) -> String {
        let links = navItems(unreadCount: unreadCount).map { item in
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
        body { background-color:#fff0f5; color:#330033; font-family:Verdana,Arial,sans-serif; font-size:11px; -webkit-font-smoothing:none; }
        a { color:#cc0066; }
        a:visited { color:#cc0066; }
        a.active { font-weight:bold; }
        .banner { font-family:Verdana,Arial,sans-serif; font-size:30px; font-weight:bold; color:#cc0066; letter-spacing:2px; }
        .bannerheart { color:#ff99bb; }
        .tagline { font-size:12px; color:#886688; }
        .nav { font-size:11px; }
        .warning { color:#cc6666; }
        .footer { color:#998899; }
        .about { color:#665566; }
        .photo { color:#aa88aa; font-style:italic; }
        table { border-collapse:collapse; }
        td, th { padding:4px 8px; }
        th { color:#ffffff; background-color:#cc0066; }
        .entry { background-color:#ffffff; border:1px solid #eeccdd; }
        .city { color:#886688; }
        .sect { color:#cc0066; font-weight:bold; }
        .composebtn { font-family:Verdana,Arial,sans-serif; font-size:11px; }
        .chat { font-size:11px; }
        .chat .mine { background-color:#ffe4ef; }
        .chat td { border-bottom:1px solid #f2dce4; }
        .attachlist { color:#886688; }
        </style>
        </head>
        <body>
        <center>
        <p class="banner"><span class="bannerheart">♥</span> LOVE.SU <span class="bannerheart">♥</span></p>
        <p class="tagline">\(escapeHTML(site.tagline))</p>
        <br>
        \(navHTML)
        <table width="640" cellpadding="6" cellspacing="0" border="1"><tr><td bgcolor="#ffffff" align="center">
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

    static func indexBody(content: LoveContent) -> String {
        guard !content.profiles.isEmpty else {
            return "<p>Анкет пока нет — загляните позже.</p>\n"
        }
        let rows = content.profiles.map { profile in
            let about = String(profile.about.prefix(80))
            let suffix = profile.about.count > 80 ? "…" : ""
            return """
            <tr class="entry"><td align="left"><a href="\(baseURL)/profile/\(escapeHTML(profile.id))"><b>\(escapeHTML(profile.nickname))</b></a></td><td>\(profile.age)</td><td class="city">\(escapeHTML(profile.city))</td><td align="left" class="about">\(escapeHTML(about + suffix))</td></tr>
            """
        }.joined(separator: "\n")
        return """
        <p class="sect">Найди свою вторую половинку</p>
        <table width="100%">
        <tr><th>Ник</th><th>Возраст</th><th>Город</th><th>О себе</th></tr>
        \(rows)
        </table>
        """
    }

    static func profileBody(profile: LoveContent.Profile) -> String {
        let interests = profile.interests
            .map { "<li>\(escapeHTML($0))</li>" }
            .joined(separator: "")
        let interestsHTML = interests.isEmpty
            ? "<p class=\"about\">Интересы не указаны.</p>"
            : "<ul align=\"left\">\(interests)</ul>"
        let chatURL = "\(baseURL)/mail/\(escapeHTML(profile.id))"
        return """
        <p class="sect">\(escapeHTML(profile.nickname)), \(profile.age), \(escapeHTML(profile.city))</p>
        <p class="photo" align="left">\(escapeHTML(profile.photoPlaceholder))</p>
        <p align="left" class="about">\(escapeHTML(profile.about))</p>
        <p align="left" class="sect">Интересы:</p>
        \(interestsHTML)
        <p align="left" class="sect">Ищет:</p>
        <p align="left" class="about">\(escapeHTML(profile.lookingFor))</p>
        <p align="left"><a class="composebtn" href="\(chatURL)"><b>✉ Написать сообщение</b></a></p>
        <p><a href="\(baseURL)/">← Все анкеты</a></p>
        """
    }

    static func aboutBody(content: LoveContent) -> String {
        return """
        <p class="sect">\(escapeHTML(content.site.title))</p>
        <p align="left" class="about">\(escapeHTML(content.site.tagline))</p>
        <p align="left" class="about">Сайт работает с 1999 года. Анкеты регистрируются бесплатно, переписка — через внутренний чат: напишите сообщение на анкете, и собеседник ответит уже через несколько секунд.</p>
        <p align="left" class="about">Вопросы и пожелания — на <a href="http://pochta.su">Pochta.su</a>.</p>
        """
    }

    // MARK: - Переписка (внутренний мессенджер)

    struct ThreadSummary {
        let id: String
        let nickname: String
        let age: Int
        let lastMessage: String
        let lastTimestamp: Date
        let unreadCount: Int
    }

    static func mailBody(threads: [ThreadSummary]) -> String {
        guard !threads.isEmpty else {
            return "<p class=\"sect\">Переписка</p><p class=\"about\">Переписок пока нет. Начните с анкеты: откройте профиль и напишите сообщение.</p>"
        }
        let rows = threads.map { thread in
            let stamp = timestampText(thread.lastTimestamp)
            let unread = thread.unreadCount > 0 ? " <b>(\(thread.unreadCount))</b>" : ""
            return """
            <tr class="entry"><td align="left"><a href="\(baseURL)/mail/\(escapeHTML(thread.id))"><b>\(escapeHTML(thread.nickname))</b></a>, \(thread.age)</td><td align="left" class="about">\(escapeHTML(thread.lastMessage))</td><td class="city">\(stamp)</td><td align="left">\(unread)</td></tr>
            """
        }.joined(separator: "\n")
        return """
        <p class="sect">Переписка</p>
        <table width="100%">
        <tr><th>Собеседник</th><th>Последнее сообщение</th><th>Когда</th><th></th></tr>
        \(rows)
        </table>
        """
    }

    static func threadBody(
        profile: LoveContent.Profile,
        messages: [LoveState.ChatMessage],
        attachmentName: String?,
        attachableFiles: [FileInstance]
    ) -> String {
        let history = messages.map { message -> String in
            let who = message.sender == .player ? "ВЫ" : escapeHTML(profile.nickname).uppercased()
            let cls = message.sender == .player ? "mine" : ""
            let attachmentHTML: String
            if let name = message.attachmentName {
                attachmentHTML = "<p class=\"attachlist\" align=\"left\">📎 \(escapeHTML(name))</p>"
            } else {
                attachmentHTML = ""
            }
            return """
            <tr class="chat"><td class="\(cls)" align="left"><b>\(who)</b> (\(Self.timestampText(message.timestamp)))<br>\(message.textHTML)\(attachmentHTML)</td></tr>
            """
        }.joined(separator: "\n")

        let attachOptions = attachableFiles.map { file in
            "<option value=\"\(escapeHTML(file.instanceId))\"\(attachmentName == file.content.name ? " selected" : "")>\(escapeHTML(file.content.name)) (\(FileSizeFormatter.format(file.content.sizeBytes)))</option>"
        }.joined(separator: "\n")
        let attachHTML = attachOptions.isEmpty
            ? "<p class=\"attachlist\">Файлов для вложения нет.</p>"
            : "<select name=\"attachment\" style=\"width:100%\"><option value=\"\">— без файла —</option>\(attachOptions)</select>"

        return """
        <p class="sect">Переписка: \(escapeHTML(profile.nickname)), \(profile.age)</p>
        <table class="chat" width="100%">
        \(history.isEmpty ? "<tr><td class=\"about\">Сообщений пока нет. Напишите первым!</td></tr>" : history)
        </table>
        <br>
        <form method="get" action="\(baseURL)/mail/send">
        <input type="hidden" name="profileID" value="\(escapeHTML(profile.id))">
        <table width="100%">
        <tr><td align="left"><textarea name="text" rows="4" style="width:100%"></textarea></td></tr>
        <tr><td align="left" class="about">Вложение (не обязательно):</td></tr>
        <tr><td align="left">\(attachHTML)</td></tr>
        <tr><td align="left"><input type="submit" value="Отправить"></td></tr>
        </table>
        </form>
        <p><a href="\(baseURL)/mail">← Все переписки</a></p>
        """
    }

    // MARK: - Helpers

    static func plainText(fromHTML html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: "<br>", with: "\n")
        text = text.replacingOccurrences(of: "<br/>", with: "\n")
        text = text.replacingOccurrences(of: "<br />", with: "\n")
        text = text.replacingOccurrences(of: "</p>", with: "\n")
        while let open = text.firstIndex(of: "<"), let close = text[open...].firstIndex(of: ">") {
            text.removeSubrange(open...close)
        }
        let entities = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"),
            ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")
        ]
        for (from, to) in entities {
            text = text.replacingOccurrences(of: from, with: to)
        }
        return text
    }

    private static func timestampText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter.string(from: date)
    }

    static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}