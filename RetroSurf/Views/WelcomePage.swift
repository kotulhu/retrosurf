import Foundation

enum WelcomePage {
    static let url = "welcome.retrosurf.local"

    static let html = """
    <!DOCTYPE HTML>
    <html lang="ru">
    <head>
    <meta charset="utf-8">
    <title>RetroSurf</title>
    <style>
    body { background-color:#e6e2d8; font-family:"Times New Roman","Georgia",serif; color:#222222; margin:0; }
    h1 { margin-top:26px; }
    td, th { padding:6px 14px; }
    table { border-collapse:collapse; background-color:#f4f0e6; }
    .blink { animation: blink 1.2s step-end infinite; }
    @keyframes blink { 50% { opacity:0; } }
    .counter { color:#666666; font-family:"Courier New",monospace; font-size:12px; }
    </style>
    </head>
    <body>
    <center>
    <h1>Добро пожаловать в <font color="#663399"><i>RetroSurf</i></font></h1>
    <marquee behavior="scroll" direction="left" scrollamount="7" width="540">* лучший браузер эпохи модемов * ручная настройка PPP * вебмастер заплатил провайдеру за этот трафик *</marquee>
    <hr width="560" color="#886644">
    <table border="2" cellspacing="0" cellpadding="8" width="560">
    <tr>
    <td align="center" bgcolor="#e8e8ff"><b><a href="http://pochta.su/"><font size="4">📧 Pochta.su — бесплатная электронная почта</font></a></b><br><small>зарегистрируйте ваш первый в России бесплатный ящик</small></td>
    </tr>
    </table>
    <br>
    <table border="2" cellspacing="0" cellpadding="8" width="560">
    <tr>
    <th colspan="2" bgcolor="#ddd6c6">Страница-приветствие</th>
    </tr>
    <tr>
    <td align="center" width="260"><font color="#663399"><b>Netscape Navigator</b></font><br><small>серо-сиреневая классика</small></td>
    <td align="center" width="260"><font color="#1a55a5"><b>Internet Explorer</b></font><br><small>сине-голубая классика</small></td>
    </tr>
    <tr>
    <td colspan="2" align="center">Переключите скин в тулбаре — оболочка сменится мгновенно.</td>
    </tr>
    </table>
    <br>
    <span class="blink"><font color="#cc0000">Страница всё ещё строится…</font></span>
    <br><br>
    <div class="counter">Сейчас на сайте уже 128 посетителей (но это точно не вы).</div>
    <small>(c) 1996 RetroSurf. Оптимизировано для Netscape 3.0 и Internet Explorer 4.0.</small>
    </center>
    </body>
    </html>
    """
}