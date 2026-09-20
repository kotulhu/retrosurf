import Foundation

enum MailTemplates {
    static let baseURL = "http://pochta.su"

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter
    }()

    private static func css() -> String {
        """
        body { background:#ffffff; color:#000000; font-family:Verdana,Arial,sans-serif; font-size:11px; margin:0; padding:0; }
        a { color:#0000cc; text-decoration:underline; }
        a:visited { color:#551a8b; }
        .frame { width:600px; margin:0 auto; padding:12px 0 24px 0; }
        .logo { color:#0000cc; font-size:16px; font-weight:bold; }
        .rule { border:0; border-top:1px solid #999999; }
        .nav { color:#000000; }
        .nav a { margin-right:2px; }
        table { border-collapse:collapse; }
        .form td { padding:3px 6px; }
        .form input, .form textarea { font-family:Verdana,Arial,sans-serif; font-size:11px; }
        .inbox th { background:#e8e8ff; text-align:left; padding:3px 8px; border:1px solid #cccccc; }
        .inbox td { border:1px solid #cccccc; padding:3px 8px; }
        .error { color:#cc0000; font-weight:bold; }
        .footer { margin-top:18px; color:#666666; }
        """
    }

    private static func shell(title: String, loggedIn: Bool, body: String) -> String {
        let header: String
        if loggedIn {
            header = """
            <div class="logo">Pochta.su</div>
            <hr class="rule">
            <div class="nav"><a href="\(baseURL)/inbox">Входящие</a> · <a href="\(baseURL)/compose">Написать</a> · <a href="\(baseURL)/sent">Отправленные</a> · <a href="\(baseURL)/logout">Выход</a></div>
            <hr class="rule">
            """
        } else {
            header = ""
        }
        return """
        <!DOCTYPE HTML>
        <html lang="ru">
        <head>
        <meta charset="utf-8">
        <title>\(title)</title>
        <style>
        \(css())
        </style>
        </head>
        <body>
        <div class="frame">
        \(header)
        \(body)
        <div class="footer">Счётчик посещений: 001337</div>
        </div>
        </body>
        </html>
        """
    }

    static func registerPage(error: String?) -> String {
        var body = "<h2>Регистрация почтового ящика</h2>\n"
        body += "<p>Один ящик на человека. Бесплатно навсегда.</p>\n"
        if let error {
            body += "<p class=\"error\">\(escapeHTML(error))</p>\n"
        }
        body += """
        <form method="get" action="\(baseURL)/register">
        <table class="form" border="0" cellspacing="0" cellpadding="4">
        <tr><td>Логин:</td><td><input type="text" name="username" size="24"></td></tr>
        <tr><td>Пароль:</td><td><input type="password" name="password" size="24"></td></tr>
        <tr><td>Ваше имя:</td><td><input type="text" name="displayName" size="24"></td></tr>
        <tr><td></td><td><input type="submit" value="Создать ящик"></td></tr>
        </table>
        </form>
        """
        return shell(title: "Pochta.su — регистрация", loggedIn: false, body: body)
    }

    static func loginPage(error: String?) -> String {
        var body = "<h2>Вход в почтовый ящик</h2>\n"
        if let error {
            body += "<p class=\"error\">\(escapeHTML(error))</p>\n"
        }
        body += """
        <form method="get" action="\(baseURL)/login">
        <table class="form" border="0" cellspacing="0" cellpadding="4">
        <tr><td>Логин:</td><td><input type="text" name="username" size="24"></td></tr>
        <tr><td>Пароль:</td><td><input type="password" name="password" size="24"></td></tr>
        <tr><td></td><td><input type="submit" value="Войти"></td></tr>
        </table>
        </form>
        <p>Нет ящика? <a href="\(baseURL)/register">Зарегистрировать новый</a></p>
        """
        return shell(title: "Pochta.su — вход", loggedIn: false, body: body)
    }

    static func inboxPage(messages: [SiteMailMessage], account: MailAccount) -> String {
        let list = messages.filter { $0.folder == .inbox }
            .sorted { $0.timestamp > $1.timestamp }
        var body = "<h2>Входящие</h2>\n"
        if list.isEmpty {
            body += "<p>У вас нет писем.</p>\n"
        } else {
            body += """
            <table class="inbox" cellspacing="0" cellpadding="0">
            <tr><th>От</th><th>Тема</th><th>Дата</th></tr>
            """
            for message in list {
                let subject = message.isRead
                    ? escapeHTML(message.subject)
                    : "<b>\(escapeHTML(message.subject))</b>"
                body += "<tr><td>\(escapeHTML(message.from))</td><td><a href=\"\(baseURL)/message/\(message.id)\">\(subject)</a></td><td>\(dateFormatter.string(from: message.timestamp))</td></tr>\n"
            }
            body += "</table>\n"
        }
        return shell(title: "Pochta.su — входящие", loggedIn: true, body: body)
    }

    static func sentPage(messages: [SiteMailMessage], account: MailAccount) -> String {
        let list = messages.filter { $0.folder == .sent }
            .sorted { $0.timestamp > $1.timestamp }
        var body = "<h2>Отправленные</h2>\n"
        if list.isEmpty {
            body += "<p>Вы ещё не отправляли писем.</p>\n"
        } else {
            body += """
            <table class="inbox" cellspacing="0" cellpadding="0">
            <tr><th>Кому</th><th>Тема</th><th>Дата</th></tr>
            """
            for message in list {
                let subject = message.isRead
                    ? escapeHTML(message.subject)
                    : "<b>\(escapeHTML(message.subject))</b>"
                body += "<tr><td>\(escapeHTML(message.to))</td><td><a href=\"\(baseURL)/message/\(message.id)\">\(subject)</a></td><td>\(dateFormatter.string(from: message.timestamp))</td></tr>\n"
            }
            body += "</table>\n"
        }
        return shell(title: "Pochta.su — отправленные", loggedIn: true, body: body)
    }

    static func letterPage(message: SiteMailMessage, account: MailAccount) -> String {
        let body = """
        <h2>Письмо</h2>
        <table class="form" border="0" cellspacing="0" cellpadding="3">
        <tr><td><b>От:</b></td><td>\(escapeHTML(message.from))</td></tr>
        <tr><td><b>Кому:</b></td><td>\(escapeHTML(message.to))</td></tr>
        <tr><td><b>Тема:</b></td><td>\(escapeHTML(message.subject))</td></tr>
        <tr><td><b>Дата:</b></td><td>\(dateFormatter.string(from: message.timestamp))</td></tr>
        </table>
        <hr class="rule">
        \(message.bodyHTML)
        <hr class="rule">
        <p><a href="\(baseURL)/compose">Ответить</a> &nbsp;&nbsp; <a href="\(baseURL)/inbox">← К списку</a></p>
        """
        return shell(title: "Pochta.su — письмо", loggedIn: true, body: body)
    }

    static func composePage(account: MailAccount) -> String {
        let body = """
        <h2>Новое письмо</h2>
        <form method="get" action="\(baseURL)/compose">
        <table class="form" border="0" cellspacing="0" cellpadding="3">
        <tr><td>Кому:</td><td><input type="text" name="to" size="40"></td></tr>
        <tr><td>Тема:</td><td><input type="text" name="subject" size="40"></td></tr>
        <tr><td valign="top">Текст:</td><td><textarea name="body" rows="10" cols="48"></textarea></td></tr>
        <tr><td></td><td><input type="submit" value="Отправить"></td></tr>
        </table>
        </form>
        """
        return shell(title: "Pochta.su — написать", loggedIn: true, body: body)
    }

    static func escapeHTML(_ text: String) -> String {
        var s = text
        for (from, to) in [
            ("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"), ("\"", "&quot;"), ("'", "&#39;")
        ] {
            s = s.replacingOccurrences(of: from, with: to)
        }
        return s
    }
}