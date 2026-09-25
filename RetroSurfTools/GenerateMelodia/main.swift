import Foundation

// ---------------------------------------------------------------------------
// GenerateMelodia — однократный детерминированный генератор контента melodia.su.
//
// Пишет:
//   Resources/sites/melodia.su/catalog.json
//   Resources/sites/melodia.su/categories/{id}.json   (featured 4–8 треков)
//   Resources/sites/melodia.su/generated/{id}/_meta.json + chunk_000.json
//
// Запуск:
//   swift RetroSurfTools/GenerateMelodia/main.swift
//
// Размеры в самом узком смысле «правдоподобны для диалапа»: выкачиваются за
// 3–45 минут на 33.6k/56k. hasVirus всегда false. Всё строго детерминировано.
// ---------------------------------------------------------------------------

// MARK: - Output models (локальные, повторяют JSON-схему приложения)

struct FileEntry: Codable, Sendable {
    let id: String
    let name: String
    let sizeBytes: Int
    let description: String
    let hasVirus: Bool
}

struct CategoryFile: Codable, Sendable {
    let id: String
    let title: String
    let description: String
    let files: [FileEntry]
}

struct MetaFile: Codable, Sendable {
    let totalEntries: Int
    let chunkSize: Int
    let chunkCount: Int
}

struct CatalogRoot: Codable, Sendable {
    let site: [String: String]
    let categories: [CategoryRef]

    struct CategoryRef: Codable, Sendable {
        let id: String
        let file: String
    }
}

// MARK: - Deterministic RNG (splitmix64 по seed от имени категории)

func fnv1a64(_ string: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash &*= 0x100000001b3
    }
    return hash
}

struct DeterministicLCG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= (z >> 31)
        return z
    }
}

// MARK: - Featured files (приложение к ТЗ, с поправками размеров под диапазоны)

struct FeaturedSpec {
    let name: String
    let sizeBytes: Int
    let description: String
}

struct CategorySpec {
    let id: String
    let title: String
    let description: String
    let filePrefix: String
    let sizeMin: Int
    let sizeMax: Int
    let descTemplates: [String]
    let featured: [FeaturedSpec]
}

func featured(_ id: String, _ name: String, _ size: Int, _ desc: String) -> FeaturedSpec {
    FeaturedSpec(name: name, sizeBytes: size, description: desc)
}

let categories: [CategorySpec] = [
    CategorySpec(
        id: "russian_rock",
        title: "Русский рок",
        description: "Цой, Наутилус, ДДТ, Ария и другие. Говорят, что под это лучше всего качать по модему.",
        filePrefix: "rr",
        sizeMin: 3_500_000,
        sizeMax: 5_500_000,
        descTemplates: ["Русский рок — трек #{{n}}.", "Запись #{{n}}. Андеграунд.", "Раритет #{{n}}. Концертная запись."],
        featured: [
            featured("mr_kino_gruppa_krovi", "kino_gruppa_krovi.mp3", 4_100_000, "Кино — Группа крови (1988)."),
            featured("mr_kino_vosmisklassnitsa", "kino_vosmisklassnitsa.mp3", 3_900_000, "Кино — Восьмиклассница. Студийная запись."),
            featured("mr_nautilus_dyhanie", "nautilus_dyhanie.mp3", 4_400_000, "Наутилус Помпилиус — Дыхание."),
            featured("mr_nautilus_progulki", "nautilus_progulki.mp3", 4_200_000, "Наутилус Помпилиус — Прогулки по воде."),
            featured("mr_ddt_dozhd", "ddt_dozhd.mp3", 4_300_000, "ДДТ — Дождь."),
            featured("mr_alisa_nebo", "alisa_nebo.mp3", 3_700_000, "Алиса — Небо славян."),
            featured("mr_aria_ulitsa_roz", "aria_ulitsa_roz.mp3", 4_500_000, "Ария — Улица роз."),
            featured("mr_chaif_argentina", "chaif_argentina.mp3", 3_600_000, "Чайф — Аргентина, Ямайка, 5:0."),
        ]
    ),
    CategorySpec(
        id: "foreign_rock",
        title: "Зарубежный рок",
        description: "Metallica, Scorpions, Nirvana, Queen, Led Zeppelin.",
        filePrefix: "fr",
        sizeMin: 3_500_000,
        sizeMax: 5_500_000,
        descTemplates: ["Rock track #{{n}}.", "Live recording #{{n}}.", "Classic rock #{{n}}."],
        featured: [
            featured("mr_metallica_enter_sandman", "metallica_enter_sandman.mp3", 5_100_000, "Metallica — Enter Sandman."),
            featured("mr_metallica_nothing_else_matters", "metallica_nothing_else_matters.mp3", 5_300_000, "Metallica — Nothing Else Matters."),
            featured("mr_scorpions_wind_of_change", "scorpions_wind_of_change.mp3", 4_900_000, "Scorpions — Wind of Change."),
            featured("mr_nirvana_smells_like_teen_spirit", "nirvana_smells_like_teen_spirit.mp3", 4_200_000, "Nirvana — Smells Like Teen Spirit."),
            featured("mr_queen_bohemian_rhapsody", "queen_bohemian_rhapsody.mp3", 5_400_000, "Queen — Bohemian Rhapsody."),
            featured("mr_led_zeppelin_stairway", "led_zeppelin_stairway.mp3", 5_500_000, "Led Zeppelin — Stairway to Heaven."),
            featured("mr_pink_floyd_another_brick", "pink_floyd_another_brick.mp3", 5_400_000, "Pink Floyd — Another Brick in the Wall."),
        ]
    ),
    CategorySpec(
        id: "russian_pop",
        title: "Русская поп-музыка",
        description: "Мумий Тролль, Земфира, Иванушки, Руки Вверх.",
        filePrefix: "rp",
        sizeMin: 3_500_000,
        sizeMax: 5_500_000,
        descTemplates: ["Поп-хит #{{n}}.", "Танцевальный трек #{{n}}.", "Радиоверсия #{{n}}."],
        featured: [
            featured("mr_mumiy_troll_vladivostok_2000", "mumiy_troll_vladivostok_2000.mp3", 4_400_000, "Мумий Тролль — Владивосток 2000."),
            featured("mr_mumiy_troll_nevesta", "mumiy_troll_nevesta.mp3", 3_900_000, "Мумий Тролль — Невеста."),
            featured("mr_zemfira_romashki", "zemfira_romashki.mp3", 3_800_000, "Земфира — Ромашки."),
            featured("mr_zemfira_arivederchi", "zemfira_arivederchi.mp3", 4_000_000, "Земфира — Ариведерчи."),
            featured("mr_ivanushki_top_top", "ivanushki_top_top.mp3", 3_600_000, "Иванушки International — Тополиный пух."),
            featured("mr_ruki_vverh_kroshka", "ruki_vverh_kroshka.mp3", 3_500_000, "Руки Вверх — Крошка моя."),
            featured("mr_splean_romans", "splean_romans.mp3", 3_700_000, "Сплин — Романс."),
        ]
    ),
    CategorySpec(
        id: "foreign_pop",
        title: "Зарубежная поп-музыка",
        description: "Michael Jackson, Madonna, Backstreet Boys, Britney Spears.",
        filePrefix: "fp",
        sizeMin: 3_500_000,
        sizeMax: 5_500_000,
        descTemplates: ["Pop hit #{{n}}.", "Radio edit #{{n}}.", "Dance track #{{n}}."],
        featured: [
            featured("mr_michael_jackson_billie_jean", "michael_jackson_billie_jean.mp3", 4_700_000, "Michael Jackson — Billie Jean."),
            featured("mr_michael_jackson_beat_it", "michael_jackson_beat_it.mp3", 4_900_000, "Michael Jackson — Beat It."),
            featured("mr_madonna_frozen", "madonna_frozen.mp3", 5_200_000, "Madonna — Frozen."),
            featured("mr_backstreet_boys_i_want_it", "backstreet_boys_i_want_it.mp3", 4_200_000, "Backstreet Boys — I Want It That Way."),
            featured("mr_spice_girls_wannabe", "spice_girls_wannabe.mp3", 3_800_000, "Spice Girls — Wannabe."),
            featured("mr_britney_spears_baby_one_more", "britney_spears_baby_one_more.mp3", 4_100_000, "Britney Spears — …Baby One More Time."),
        ]
    ),
    CategorySpec(
        id: "electronic",
        title: "Электроника",
        description: "The Prodigy, Massive Attack, Enigma, Aphex Twin.",
        filePrefix: "el",
        sizeMin: 3_500_000,
        sizeMax: 5_500_000,
        descTemplates: ["Electronic track #{{n}}.", "Club mix #{{n}}.", "Ambient piece #{{n}}."],
        featured: [
            featured("mr_prodigy_firestarter", "prodigy_firestarter.mp3", 4_300_000, "The Prodigy — Firestarter."),
            featured("mr_prodigy_breathe", "prodigy_breathe.mp3", 4_400_000, "The Prodigy — Breathe."),
            featured("mr_massive_attack_teardrop", "massive_attack_teardrop.mp3", 4_800_000, "Massive Attack — Teardrop."),
            featured("mr_enigma_return_to_innocence", "enigma_return_to_innocence.mp3", 4_600_000, "Enigma — Return to Innocence."),
            featured("mr_aphex_twin_windowlicker", "aphex_twin_windowlicker.mp3", 5_000_000, "Aphex Twin — Windowlicker."),
        ]
    ),
    CategorySpec(
        id: "classical",
        title: "Классика",
        description: "Бах, Вивальди, Чайковский, Рахманинов. Записи крупнее — симфонии длинные.",
        filePrefix: "cl",
        sizeMin: 5_000_000,
        sizeMax: 9_000_000,
        descTemplates: ["Классика. Запись #{{n}}.", "Симфония #{{n}}.", "Оркестровая запись #{{n}}."],
        featured: [
            featured("mr_bach_toccata_fugue", "bach_toccata_fugue.mp3", 5_200_000, "Бах — Токката и фуга ре минор."),
            featured("mr_vivaldi_four_seasons_spring", "vivaldi_four_seasons_spring.mp3", 5_800_000, "Вивальди — Времена года, Весна."),
            featured("mr_vivaldi_four_seasons_winter", "vivaldi_four_seasons_winter.mp3", 5_600_000, "Вивальди — Времена года, Зима."),
            featured("mr_tchaikovsky_swan_lake", "tchaikovsky_swan_lake.mp3", 6_200_000, "Чайковский — Лебединое озеро."),
            featured("mr_rachmaninov_vocalise", "rachmaninov_vocalise.mp3", 5_100_000, "Рахманинов — Вокализ."),
        ]
    ),
    CategorySpec(
        id: "jazz_blues",
        title: "Джаз и блюз",
        description: "Louis Armstrong, Ella Fitzgerald, Miles Davis, Billie Holiday.",
        filePrefix: "jz",
        sizeMin: 4_000_000,
        sizeMax: 7_000_000,
        descTemplates: ["Jazz standard #{{n}}.", "Blues #{{n}}.", "Live at the club #{{n}}."],
        featured: [
            featured("mr_louis_armstrong_wonderful_world", "louis_armstrong_wonderful_world.mp3", 4_700_000, "Louis Armstrong — What a Wonderful World."),
            featured("mr_ella_fitzgerald_summertime", "ella_fitzgerald_summertime.mp3", 5_100_000, "Ella Fitzgerald — Summertime."),
            featured("mr_miles_davis_so_what", "miles_davis_so_what.mp3", 6_500_000, "Miles Davis — So What."),
            featured("mr_billie_holiday_strange_fruit", "billie_holiday_strange_fruit.mp3", 4_900_000, "Billie Holiday — Strange Fruit."),
        ]
    ),
    CategorySpec(
        id: "soundtracks",
        title: "Саундтреки",
        description: "Из «Матрицы», «Титаника», «Леона» и «Криминального чтива».",
        filePrefix: "st",
        sizeMin: 3_500_000,
        sizeMax: 5_500_000,
        descTemplates: ["Саундтрек #{{n}}.", "Из кинофильма #{{n}}.", "Film score #{{n}}."],
        featured: [
            featured("mr_titanic_my_heart_will_go_on", "titanic_my_heart_will_go_on.mp3", 5_100_000, "Celine Dion — My Heart Will Go On («Титаник»)."),
            featured("mr_matrix_clubbed_to_death", "matrix_clubbed_to_death.mp3", 4_800_000, "Rob Dougan — Clubbed to Death («Матрица»)."),
            featured("mr_leon_shape_of_my_heart", "leon_shape_of_my_heart.mp3", 4_600_000, "Sting — Shape of My Heart («Леон»)."),
            featured("mr_pulp_fiction_miserlou", "pulp_fiction_miserlou.mp3", 4_300_000, "Dick Dale — Misirlou («Криминальное чтиво»)."),
        ]
    ),
]

let catalogSite = [
    "title": "Мелодия — архив музыки",
    "tagline": "Хорошая музыка, проверенная временем.",
    "warning": "Все mp3 — 128 kbps. Скачивайте, слушайте, делитесь.",
    "footer": "© Мелодия, 1999. Счётчик: 002187",
    "navLabel": "Жанры",
]

// MARK: - Output helpers

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

func outputDir() -> URL {
    let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    return scriptDir
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("RetroSurf/Resources/sites/melodia.su", isDirectory: true)
}

func write(_ value: some Encodable, to url: URL) {
    let data = try! encoder.encode(value)
    try! FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try! data.write(to: url)
}

// MARK: - Main

let root = outputDir()
try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

// catalog.json — ровно по ТЗ.
let catalogJSON = CatalogRoot(
    site: catalogSite,
    categories: categories.map { CatalogRoot.CategoryRef(id: $0.id, file: "categories/\($0.id).json") }
)
write(catalogJSON, to: root.appendingPathComponent("catalog.json"))

var observed: [(id: String, count: Int, minBytes: Int, maxBytes: Int)] = []

for spec in categories {
    // --- Featured: категорийный файл (4–8 точных записей из приложения) ---
    let featuredFiles = spec.featured.map {
        FileEntry(
            id: "mr_\($0.name.replacingOccurrences(of: ".mp3", with: ""))",
            name: $0.name,
            sizeBytes: $0.sizeBytes,
            description: $0.description,
            hasVirus: false
        )
    }
    write(
        CategoryFile(id: spec.id, title: spec.title, description: spec.description, files: featuredFiles),
        to: root.appendingPathComponent("categories/\(spec.id).json")
    )

    // --- Bulk: 300 записей, 1 чанк по 500, _meta.json ---
    var rng = DeterministicLCG(seed: fnv1a64(spec.id))
    var bulk: [FileEntry] = []
    var minSeen = Int.max
    var maxSeen = 0
    for i in 0..<300 {
        let n = i + 1
        let size: Int
        if i == 0 {
            size = spec.sizeMin            // гарантируем min = нижней границе
        } else if i == 1 {
            size = spec.sizeMax            // гарантируем max = верхней границе
        } else {
            let t = Double(rng.next()) / Double(UInt64.max)
            size = spec.sizeMin + Int(t * Double(spec.sizeMax - spec.sizeMin + 1))
        }
        minSeen = min(minSeen, size)
        maxSeen = max(maxSeen, size)
        let padded = String(format: "%04d", n)
        let name = "track_\(spec.filePrefix)_\(padded).mp3"
        let id = name.replacingOccurrences(of: ".mp3", with: "")
        let template = spec.descTemplates[i % spec.descTemplates.count]
            .replacingOccurrences(of: "{{n}}", with: "\(n)")
        bulk.append(FileEntry(id: id, name: name, sizeBytes: size, description: template, hasVirus: false))
    }
    let generatedDir = root.appendingPathComponent("generated/\(spec.id)", isDirectory: true)
    write(
        MetaFile(totalEntries: 300, chunkSize: 500, chunkCount: 1),
        to: generatedDir.appendingPathComponent("_meta.json")
    )
    write(bulk, to: generatedDir.appendingPathComponent("chunk_000.json"))

    observed.append((id: spec.id, count: bulk.count, minBytes: minSeen, maxBytes: maxSeen))
}

// MARK: - Отчёт генератора

func padded(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}

var lines: [String] = []
lines.append("GenerateMelodia: \(observed.reduce(0) { $0 + $1.count }) треков в \(observed.count) категориях")
lines.append("")
lines.append(padded("category", 14) + padded("count", 7) + padded("min bytes", 13) + padded("max bytes", 13) + padded("min min", 10) + padded("max min", 10))
lines.append(String(repeating: "-", count: 62))
for row in observed.sorted(by: { $0.id < $1.id }) {
    let minNow = Int(Double(row.minBytes) / 3300.0 / 60.0)
    let maxNow = Int(Double(row.maxBytes) / 3300.0 / 60.0)
    lines.append(
        padded(row.id, 14)
            + padded("\(row.count)", 7)
            + padded("\(row.minBytes)", 13)
            + padded("\(row.maxBytes)", 13)
            + padded("\(minNow)", 10)
            + padded("\(maxNow)", 10)
    )
}
lines.append(String(repeating: "-", count: 62))
lines.append("Все hasVirus=false. Все размеры внутри диапазонов ТЗ.")
print(lines.joined(separator: "\n"))