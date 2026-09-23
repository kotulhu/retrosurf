import Foundation

/// Подстановка случайных значений в шаблоны атмосферных писем.
/// Каждый вызов `fill(_:)` выбирает свежие случайные значения из пулов,
/// поэтому один и тот же шаблон превращается в разные письма.
enum MailPlaceholders {
    /// Заменяет известные плейсхолдеры {{...}} случайными значениями.
    /// Неизвестные плейсхолдеры остаются как есть.
    static func fill(_ template: String) -> String {
        fill(template, extra: [:])
    }

    /// Заменяет плейсхолдеры как `fill(_:)`, но парамерты `extra`
    /// переопределяют или дополняют значения по умолчанию
    /// (например, {{npc.name}} и {{npc.email}}). Неизвестные ключи
    /// остаются в шаблоне как есть.
    static func fill(_ template: String, extra: [String: String]) -> String {
        var substitutions: [(key: String, value: String)] = [
            ("{{random.male}}", Self.firstNamesMale.randomElement() ?? ""),
            ("{{random.female}}", Self.firstNamesFemale.randomElement() ?? ""),
            ("{{random.last}}", Self.lastNames.randomElement() ?? ""),
            ("{{random.city}}", Self.cities.randomElement() ?? ""),
            ("{{random.country}}", Self.countries.randomElement() ?? ""),
            ("{{random.domain}}", Self.domains.randomElement() ?? ""),
            ("{{random.amount}}", Self.amounts.randomElement() ?? ""),
            ("{{random.company}}", Self.companies.randomElement() ?? ""),
            ("{{random.job}}", Self.absurdJobs.randomElement() ?? ""),
            ("{{player.username}}", "пользователь"),
            ("{{missing.files}}", ""),
            ("{{date}}", Self.formattedDate())
        ]
        for (key, value) in extra {
            let placeholder = key.contains("{{") ? key : "{{\(key)}}"
            if let index = substitutions.firstIndex(where: { $0.key == placeholder }) {
                substitutions[index] = (placeholder, value)
            } else {
                substitutions.append((placeholder, value))
            }
        }
        var result = template
        for (key, value) in substitutions {
            result = result.replacingOccurrences(of: key, with: value)
        }
        return result
    }

    /// {{date}} — текущая дата в формате dd.MM.yyyy (локаль ru_RU).
    private static func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: Date())
    }

    static let firstNamesMale: [String] = [
        "Бакаре", "Джонсон", "Сэмюэл", "Абрахам", "Мустафа",
        "Владимир", "Геннадий", "Пётр", "Аркадий", "Феликс"
    ]

    static let firstNamesFemale: [String] = [
        "Кристалина", "Лариса", "Светлана", "Наталья", "Елена",
        "Ольга", "Мария", "Анна", "Вера", "Людмила"
    ]

    static let lastNames: [String] = [
        "Тунде", "Нельсон", "Окафор", "Мбекки", "Ковальски",
        "Петров", "Сидоров", "Барабанов", "Курочкин", "Огурцов"
    ]

    static let cities: [String] = [
        "Лагос", "Москва", "Санкт-Петербург", "Новосибирск", "Воронеж",
        "Самара", "Краснодар", "Екатеринбург", "Одесса", "Киев"
    ]

    static let countries: [String] = [
        "Нигерии", "Ганы", "Лимпопо", "Зимбабве", "Конго", "Сьерра-Леоне"
    ]

    static let domains: [String] = [
        "mail.ru", "pochta.su", "chat.ru", "hotmail.com", "yahoo.com", "subscribe.su"
    ]

    static let amounts: [String] = [
        "1 000 000", "5 000 000", "15 000 000", "46 000 000", "100 000", "500 000"
    ]

    static let companies: [String] = [
        "Рога и Копыта", "Гербалайф-Москва", "Хопёр-Инвест", "МММ-Лотерея",
        "Всё для дома", "Супер-Приз"
    ]

    static let absurdJobs: [String] = [
        "первый нигерийский космонавт",
        "министр нефти",
        "личный ассистент Ходорковского",
        "наследный принц Зимбабве",
        "директор цирка на Цветном",
        "ведущий специалист по астронавтике"
    ]
}