import Foundation

/// Лёгкая «бумажная» тема Мелодии: белый лист, чёрный текст, синие
/// подчёркнутые ссылки. Заметно светлее files.su (#c0c0c0) и «Полнолуния»
/// (#000033/#ccccff). Никакой выдуманный в Swift текст — только то, что
/// приходит из catalog.json, плюс структурные подписи интерфейса.
enum MelodiaTemplates {
    static func fullHTML(title: String, tagline: String, warning: String,
                         nav: String, footer: String, body: String) -> String {
        """
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(esc(title))</title>
        <style>
        body { background: #ffffff; color: #000000;
               font-family: Verdana, Arial, sans-serif; font-size: 11px; margin: 12px; }
        a { color: #0000cc; text-decoration: underline; }
        a:visited { color: #551a8b; }
        a:active { color: #ff0000; }
        h1 { color: #000000; font-weight: bold; font-size: 18px; margin: 0 0 2px 0; }
        .tagline { font-style: italic; color: #666666; margin: 0 0 8px 0; }
        .nav { margin: 8px 0; }
        .nav a { margin-right: 4px; }
        .warning { color: #666666; font-style: italic; margin: 8px 0; }
        table { border-collapse: collapse; margin-top: 8px; }
        td, th { border: 1px solid #cccccc; padding: 3px 8px;
                 font-size: 11px; text-align: left; }
        th { background: #f0f0f0; }
        hr { border: 0; border-top: 1px solid #cccccc; margin: 10px 0; }
        .footer { color: #999999; margin-top: 14px; font-size: 10px; }
        .pager { margin-top: 10px; }
        form { margin: 8px 0; }
        input, button { font-family: Verdana, Arial, sans-serif; font-size: 11px; }
        </style>
        </head>
        <body>
        <h1>\(esc(title))</h1>
        <p class="tagline">\(esc(tagline))</p>
        \(nav)
        <hr>
        <p class="warning">\(esc(warning))</p>
        \(body)
        <hr>
        <p class="footer">\(esc(footer))</p>
        </body>
        </html>
        """
    }

    /// GET-форма подстрокового поиска по файлам категории.
    static func searchBox(action: URL, query: String) -> String {
        "<form method=\"get\" action=\"\(action.absoluteString)\">"
            + "<input type=\"text\" name=\"q\" value=\"\(esc(query))\" size=\"24\"> "
            + "<input type=\"submit\" value=\"Поиск\"></form>\n"
    }

    private static func esc(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}