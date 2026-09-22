import Foundation

/// HTML-шаблоны домашней странички — 3 фона, подстановка цветов, «Обо мне».
enum HomepageTemplates {
    static func catalogPage(state: HomepageState, notice: String? = nil) -> String {
        let catalog = [
            "Андрей из Самары", "Лена и её кот Барсик", "Димон 2000", "Наташа Солнечная",
            "Серёга Воронеж", "Катюша", "Михаил, 11-Б", "Оля любит аниме",
            "Вовка-Рокер", "Марина", "Паша из сети", "Света", "Игорь",
            "Таня", "Макс", "Люба", "Рома", "Ксюша", "Денис", "Аня"
        ]
        let catalogLinks = catalog.enumerated().map { index, name in
            "<li><a href=\"/p/\(index + 1).html\">\(name)</a></li>"
        }.joined()
        let recent = [
            (20, "Аня"), (19, "Денис"), (18, "Ксюша"), (17, "Рома"), (16, "Люба")
        ].map { number, name in
            "<li><a href=\"/p/\(number).html\">\(name)</a></li>"
        }.joined()
        let accountBlock: String
        if let session = state.session {
            accountBlock = "<p class=\"hint\">Вы вошли как <b>\(escapeHTML(session.login))</b>.<br><a href=\"/editor\">Редактировать страницу</a><br><a href=\"/my-page\">Посмотреть страницу</a><br><a href=\"/logout\">Выйти</a></p>"
        } else if state.account != nil {
            accountBlock = "<p class=\"hint\">Уже зарегистрированы? Войдите в свой аккаунт.</p>"
        } else {
            accountBlock = "<p class=\"hint\">Регистрация бесплатная!</p>"
        }
        let noticeBlock = notice.map { "<p class=\"notice\">\(escapeHTML($0))</p>" } ?? ""
        let authenticationForms: String
        if state.session != nil {
            authenticationForms = accountBlock
        } else {
            authenticationForms = """
            <form method="get" action="http://homepage.su/login"><b>Логин:</b><input class="field" type="text" name="login"><b>Пароль:</b><input class="field" type="password" name="password"><input class="button" type="submit" value="Войти"></form>
            <p class="hint"><a href="#">Забыли пароль?</a></p>
            <h3>Ещё не с нами?</h3>
            <form method="get" action="http://homepage.su/register"><b>Придумайте логин:</b><input class="field" type="text" name="login"><b>Пароль:</b><input class="field" type="password" name="password"><b>Ваш e-mail:</b><input class="field" type="text" name="email"><input class="button" type="submit" value="Зарегистрироваться"></form>
            \(accountBlock)
            """
        }
        return """
        <html><head><meta charset="utf-8"><title>Люди.su - личные странички</title>
        <style>
        body{margin:0;background:#e7e2cf;color:#222;font:13px 'Times New Roman',serif}
        .page{width:760px;margin:18px auto 30px}.logo{text-align:center;color:#8c1919;font-size:38px;font-weight:bold}
        .tagline{text-align:center;margin:2px 0 14px;color:#555}.columns{width:100%;border-collapse:collapse}
        .columns td{vertical-align:top;padding:0 6px}.panel{background:#fffdf4;border:1px solid #555;padding:9px}
        h2{margin:-9px -9px 9px;padding:4px 7px;background:#d6c79d;border-bottom:1px solid #555;font-size:16px;text-align:center}
        h3{margin:10px 0 4px;font-size:14px}.field{width:100%;box-sizing:border-box;margin:2px 0 6px;border:1px solid #777}
        .button{font:13px 'Times New Roman',serif;margin-top:2px}.hint{font-size:11px;color:#555}.notice{background:#e3f3d9;border:1px solid #698d58;padding:6px}.catalog{margin:0;padding-left:22px;line-height:1.45}
        a{color:#0000aa}a:visited{color:#660066}.new{color:#087d08;font-weight:bold}.footer{text-align:center;margin-top:13px;font-size:11px;color:#666}
        </style>
        </head><body>
        <div class="page">
        <div class="logo">Люди.su</div>
        <div class="tagline">Личные странички пользователей русской сети</div>
        <table class="columns"><tr>
        <td width="185"><div class="panel">
        <h2>Вход для своих</h2>
        \(authenticationForms)
        </div></td>
        <td width="385"><div class="panel">
        <h2>Каталог личных страничек</h2>
        \(noticeBlock)
        <p>Здесь живут домашние странички наших пользователей. Выберите, к кому заглянуть в гости:</p>
        <ol class="catalog">\(catalogLinks)</ol>
        <p class="hint">Хотите попасть в каталог? Зарегистрируйтесь на Люди.su.</p>
        </div></td>
        <td width="190"><div class="panel">
        <h2>Последние добавленные</h2>
        <p class="hint"><span class="new">new!</span> Свежие странички:</p>
        <ol class="catalog">\(recent)</ol>
        <p class="hint"><a href="#">Все новые странички</a></p>
        </div></td>
        </tr></table>
        <div class="footer">Люди.su &copy; 2001. Сделано людьми для людей.</div>
        </div>
        </body></html>
        """
    }

    static func stubPage(path: String) -> String {
        let name = path.replacingOccurrences(of: "/p/", with: "").replacingOccurrences(of: ".html", with: "")
        return """
        <html><head><meta charset="utf-8"><title>Личная страничка №\(name)</title>
        <style>body{background:#fff8e7;color:#333;font-family:monospace;padding:24px}</style>
        </head><body>
        <h1>Личная страничка №\(name)</h1>
        <p>Здесь скоро появится настоящее содержимое сайта.</p>
        <p><a href="/">← На главную</a></p>
        </body></html>
        """
    }

    static func publishForm(state: HomepageState) -> String {
        let bgColor = bgHex(state.background)
        let options = HomepageState.backgroundOptions.map { opt in
            let selected = opt["id"] == state.background ? " selected" : ""
            return "<option value=\"\(opt["id"] ?? "")\"\(selected)>\(opt["name"] ?? "")</option>"
        }.joined()
        return """
        <html><head><meta charset="utf-8"><title>Создать страничку</title>
        <style>body{background:#\(bgColor);color:#000;font-family:monospace;padding:28px}</style>
        </head><body>
        <h1>Создать свою страничку</h1>
        <form action="/publish" method="POST">
          <label>Фон:<select name="background">\(options)</select></label><br><br>
          <label>Цвет текста:<input name="textColor" type="color" value="#000000"></label><br><br>
          <label>Обо мне:<br><textarea name="aboutMeText" rows="4" cols="40"></textarea></label><br><br>
          <button>Опубликовать</button>
        </form></body></html>
        """
    }

    static func editorPage(state: HomepageState, notice: String? = nil, error: String? = nil) -> String {
        let noticeBlock = notice.map { "<div class=\"msg ok\">\(escapeHTML($0))</div>" } ?? ""
        let errorBlock = error.map { "<div class=\"msg err\">\(escapeHTML($0))</div>" } ?? ""
        let aboutMeText = escapeHTML(state.aboutMeText)
        let photoState = state.photoFilename == nil ? "файл не выбран" : "файл загружен"
        let photoStatus = state.photoFilename.map { "<p class=\"hint\">Текущий файл: <b>\(escapeHTML($0))</b></p>" } ?? ""
        return """
        <html><head><meta charset="utf-8"><title>Люди.su - редактор</title>
        <style>body{background:#e7e2cf;color:#222;font:14px 'Times New Roman',serif;padding:24px}.page{width:580px;margin:auto;background:#fffdf4;border:1px solid #555;padding:16px}textarea,input{width:100%;box-sizing:border-box;font:14px 'Times New Roman',serif}textarea{height:130px}
        .hint{font-size:12px;color:#555}
        .msg{font-size:13px;padding:7px;margin:8px 0;border:1px solid}
        .msg.ok{background:#e3f3d9;border-color:#698d58;color:#1f5c14}
        .msg.err{background:#f9dddd;border-color:#a44;color:#7a1a1a}
        .upload{background:#d6c79d;border:1px solid #555;padding:10px;margin:6px 0;font-size:13px}
        .upload .field{display:inline-block;width:auto;border:1px solid #777;background:#fff;padding:2px 6px;margin-right:6px}
        .upload input[type=submit]{width:auto;background:#f4f4f4;border:2px outset #ccc;padding:2px 12px;cursor:pointer;font-family:monospace}
        .actions{margin-top:14px}a{color:#0000aa}</style>
        </head><body><div class="page">
        <h1>Моя личная страничка</h1>
        <p>Расскажите о себе и добавьте фотографию.</p>
        \(noticeBlock)
        \(errorBlock)
        <form method="get" action="http://homepage.su/editor/save">
        <p><b>Текст страницы:</b><br><textarea name="aboutMeText">\(aboutMeText)</textarea></p>
        <p><b>Фотография владельца:</b></p>
        <div class="upload">
        <span class="field">\(photoState)</span>
        <input type="submit" name="pickPhoto" value="Обзор…" formaction="http://homepage.su/editor/photo">
        <p class="hint">Максимальный размер: 640&times;480, до 100 КБ. После выбора файл сохранится в локальном хранилище игры.</p>
        \(photoStatus)
        </div>
        <p class="actions"><input type="submit" value="Сохранить и опубликовать"> <a href="/my-page">Отмена</a></p>
        </form></div></body></html>
        """
    }

    static func publishedPage(
        state: HomepageState,
        isShared: Bool,
        feedbackCount: Int,
        isOwner: Bool = false,
        notice: String? = nil
    ) -> String {
        let bgColor = bgHex(state.background)
        let textColor = normalizeHex(state.textColor)
        let aboutMe = state.aboutMeText.isEmpty ? "Здесь пока пусто — загляни позже." : escapeHTML(state.aboutMeText).replacingOccurrences(of: "\n", with: "<br>")
        let photo = localPhotoHTML(filename: state.photoFilename)
        let ownerActions = isOwner ? "<p><a href=\"/editor\">Редактировать страницу</a></p>" : ""
        let noticeBlock = notice.map { "<p style=\"color:#087d08\"><b>\(escapeHTML($0))</b></p>" } ?? ""
        let invited = state.invitedFriends
        let invitesList = invited.isEmpty ? "" : "<p class=\"hint\">Ссылка отправлена:<br>\(invited.map { "📧 \(escapeHTML($0))" }.joined(separator: "<br>"))</p>"
        let counter = isShared
            ? "<p style='color:#0a0'>Отзывов получено: <b>\(feedbackCount)/3</b></p>"
            : "<p class=\"hint\">Поделитесь ссылкой с друзьями — они заглянут и оставят отзыв.</p>"
        let shareForm: String
        if isOwner {
            if invited.count < 3 {
                shareForm = """
                <form action='/share' method='get' class="share">
                <input type="text" name="email" value="" placeholder="e-mail друга (впишите любой адрес)">
                <input type="submit" value="Поделиться ссылкой">
                </form>
                """
            } else {
                shareForm = "<p style='color:#0a0'><b>Ссылка разослана трём друзьям.</b> Осталось дождаться их писем!</p>"
            }
        } else {
            shareForm = ""
        }
        return """
        <html><head><meta charset="utf-8"><title>Моя страничка</title>
        <style>body{background:#\(bgColor);color:#\(textColor);font-family:monospace;padding:28px}
        .invites{margin-top:26px;border-top:1px solid #\(textColor);padding-top:12px}
        .share{margin:8px 0}.hint{font-size:12px;opacity:.75}
        input{font:12px monospace;border:1px solid #\(textColor);padding:3px;background:#fff}
        input[type=submit]{background:#f4f4f4;margin-left:4px}</style>
        </head><body>
        <h1>Добро пожаловать на мою страничку!</h1>
        \(noticeBlock)
        <p>\(aboutMe)</p>
        \(photo)
        \(ownerActions)
        <div class="invites">
        \(counter)
        \(invitesList)
        \(shareForm)
        </div>
        </body></html>
        """
    }

    static func bgHex(_ id: String) -> String {
        switch id {
        case "clouds": return "dfe9f3"
        case "construction": return "f9e79f"
        default: return "0d1b2a" // stars
        }
    }

    static func normalizeHex(_ hex: String) -> String {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count != 6 { return "000000" }
        return value
    }

    static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func localPhotoHTML(filename: String?) -> String {
        guard let filename else { return "" }
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RetroSurf/HomepagePhotos/\(filename)")
        guard let data = try? Data(contentsOf: url) else { return "" }
        let mimeType: String
        switch url.pathExtension.lowercased() {
        case "png": mimeType = "image/png"
        case "gif": mimeType = "image/gif"
        case "webp": mimeType = "image/webp"
        default: mimeType = "image/jpeg"
        }
        return "<p><img src=\"data:\(mimeType);base64,\(data.base64EncodedString())\" alt=\"Фотография владельца страницы\" style=\"max-width:360px;max-height:360px\"></p>"
    }
}
