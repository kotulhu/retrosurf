import Foundation

/// Строит HTML личной странички игрока — классический «боёк» 90-х.
/// Имя игрока экранируется, чтобы разметку нельзя было сломать.
@MainActor
enum PlayerPageBuilder {
    /// Собирает страничку. `date` — реальная системная дата (игровые часы
    /// не используются).
    static func build(username: String, date: Date = Date()) -> String {
        let name = escapeHTML(username)
        let dateString = formattedDate(date)
        return """
        <!DOCTYPE HTML>
        <html lang="ru">
        <head>
        <meta charset="utf-8">
        <title>Личная страничка \(name)</title>
        <style>
        body { background-color:#ffffff; color:#222222; font-family:Verdana,Arial,Helvetica,sans-serif; font-size:11px; -webkit-font-smoothing:none; }
        a { color:#0000cc; }
        a:visited { color:#660099; }
        table { border-collapse:collapse; }
        .grey { font-size:10px; color:#555555; }
        </style>
        </head>
        <body>
        <center>
        <h1>Личная страничка \(name)</h1>
        <table border="0" cellpadding="6" cellspacing="0" bgcolor="#0000cc" width="520"><tr><td align="center"><font color="#ffffff" size="4"><b>\(name).homepage.su</b></font></td></tr></table>
        <br>
        <p>Привет! Меня зовут <b>\(name)</b>. Это моя первая личная страничка в интернете. Пока тут мало что есть, но я буду её дополнять — заходите почаще!</p>
        <br>
        <table border="1" cellpadding="5" cellspacing="0" width="480"><tr bgcolor="#eeeeee"><th align="center">Мои ссылки</th></tr>
        <tr><td><a href="http://pochta.su/">Почта.SU — бесплатная электронная почта</a></td></tr>
        <tr><td><a href="http://homepage.su/">Люди.su — все домашние странички</a></td></tr>
        <tr><td><a href="http://webmaster-serega.su/">Веб-мастер Серёга — сайты на заказ</a></td></tr>
        </table>
        <br>
        <p><b>Что нового</b></p>
        <ul><li><font color="#cc0000">Сайт только что открылся!</font></li></ul>
        <hr width="480" color="#0000cc">
        <p class="grey">Сайт сделан <a href="http://webmaster-serega.su/">веб-мастером Сергеем</a>. Заказать сайт: <a href="http://webmaster-serega.su/">http://webmaster-serega.su/</a></p>
        <p class="grey">Сайт находится в разработке.</p>
        <p class="grey">Вы посетитель № 000001<br>Обновлено: \(dateString)</p>
        <p class="grey">(c) 1999 \(name)</p>
        </center>
        </body>
        </html>
        """
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }

    private static func escapeHTML(_ text: String) -> String {
        var s = text
        for (from, to) in [
            ("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"), ("\"", "&quot;"), ("'", "&#39;")
        ] {
            s = s.replacingOccurrences(of: from, with: to)
        }
        return s
    }
}