#if DEBUG
import AppKit
import SwiftUI

// MARK: - Debug panel (только DEBUG)
// Отдельное окно из меню «Debug → Панель отладки». Три вкладки: объекты,
// план игры (граф квестов) и общий журнал DebugLogger. Кнопка «Сбросить
// прогресс» возвращает всё игровое состояние к чистому листу, не трогая
// AppSettings (скин, скорость модема) и встроенные Resources/sites.

struct DebugPanelView: View {
    @EnvironmentObject private var game: GameProgress
    @EnvironmentObject private var quests: QuestManager
    @EnvironmentObject private var catalog: SiteCatalog
    @EnvironmentObject private var sites: SiteSession
    @EnvironmentObject private var scheduler: MessageScheduler
    @EnvironmentObject private var questGenerator: QuestGenerator
    @EnvironmentObject private var clock: GameClock
    @EnvironmentObject private var fileQuestTracker: FileQuestTracker
    @EnvironmentObject private var loveQuestTracker: LoveQuestTracker
    @EnvironmentObject private var webmasterQuestTracker: WebmasterQuestTracker
    @EnvironmentObject private var fileStore: FileStore
    @ObservedObject private var logger = DebugLogger.shared

    @State private var tab = 0
    @State private var showResetConfirm = false
    @State private var logFilter = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TabView(selection: $tab) {
                objectsTab.tag(0)
                planTab.tag(1)
                logTab.tag(2)
            }
            .tabViewStyle(.automatic)
        }
        .frame(minWidth: 720, minHeight: 480)
        .confirmationDialog(
            "Сбросить весь игровой прогресс?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Сбросить", role: .destructive) { performReset() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Почта и личная страничка будут очищены (письма, аккаунты, отправки, фото), флаги, квесты, счёт, часы, отложенные письма и пользовательские сайты удалены. Настройки приложения (скин, скорость) не тронуты.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("Отладка RetroSurf")
                .font(.system(size: 13, weight: .bold))
            Spacer()
            Text("Игровая дата: \(GameClock.format(clock.inGameDate))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            Button("Сбросить прогресс…") { showResetConfirm = true }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Вкладка «Объекты»

    private var objectsTab: some View {
        List {
            section("GameProgress") {
                stat("score", "\(game.score)")
                stat("currentTier", "\(game.currentTier.fullLabel)")
                stat("visitedSiteIDs", "\(game.visitedSiteIDs.count) шт.")
                stat("flags", game.flags.isEmpty
                    ? "—"
                    : game.flags.sorted().joined(separator: ", "))
            }
            section("QuestManager") {
                stat("completedQuestIDs", quests.completedQuestIDs.isEmpty
                    ? "—"
                    : quests.completedQuestIDs.sorted().joined(separator: ", "))
            }
            section("MessageScheduler (pendingDeliveries)") {
                if scheduler.pendingDeliveries.isEmpty {
                    stat("pending", "—")
                } else {
                    ForEach(scheduler.pendingDeliveries) { delivery in
                        stat(
                            delivery.id.prefix(8) + " → " + delivery.targetSiteId,
                            "\(delivery.channel.rawValue), через \(Int(delivery.deliverAt.timeIntervalSinceNow)) с"
                        )
                    }
                }
            }
            section("MailSite (pochta.su inbox)") {
                if let mailSite = sites.registry.site(withID: "mail") as? MailSite {
                    if mailSite.inboxMessages.isEmpty {
                        stat("messages", "—")
                    } else {
                        stat("messages", mailSite.inboxMessages.map(\.subject).joined(separator: " | "))
                    }
                    stat("feedback (homepage)", "\((sites.registry.site(withID: "homepage-su") as? HomepageSite)?.state.feedbackCount ?? 0)/3")
                } else {
                    stat("messages", "MailSite не зарегистрирован")
                }
            }
            section("LoveQuestTracker (love.su)") {
                stat("status", loveQuestTracker.status)
                stat("flags", game.flags.filter { $0.hasPrefix("quest.love") || $0 == "artifact.love" }.sorted().joined(separator: ", "))
            }
            section("WebmasterQuestTracker (webmaster-serega.su)") {
                stat("status", webmasterQuestTracker.status)
                stat("flags", game.flags.filter { $0.hasPrefix("quest.webmaster") || $0 == "artifact.page" }.sorted().joined(separator: ", "))
            }
            section("GameClock") {
                stat("inGameDate", GameClock.format(clock.inGameDate))
            }
            section("SiteCatalog (пользовательские сайты)") {
                let userAdded = catalog.entries.filter(\.isUserAdded)
                if userAdded.isEmpty {
                    stat("entries", "—")
                } else {
                    ForEach(userAdded) { entry in
                        stat(entry.displayDomain, "id: \(entry.id)")
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Вкладка «План игры» (граф квестов)

    private var planTab: some View {
        List {
            section("Граф квестов") {
                ForEach(Array(QuestManager.questChain.enumerated()), id: \.element.quest.id) { index, step in
                    questRow(index: index, step: step)
                }
            }
            section("Каталог: разблокировки по requiredQuestID") {
                let gated = catalog.entries.filter { $0.requiredQuestID != nil }
                if gated.isEmpty {
                    stat("entries", "—")
                } else {
                    ForEach(gated) { entry in
                        stat(
                            entry.displayDomain,
                            "quest: \(entry.requiredQuestID ?? "—"), \(quests.isCompleted(entry.requiredQuestID ?? "") ? "пройден" : "не пройден")"
                        )
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func questRow(index: Int, step: QuestStep) -> some View {
        let status: String
        if quests.isCompleted(step.quest.id) {
            status = "пройден"
        } else if index == 0 || quests.isCompleted(QuestManager.questChain[index - 1].quest.id) {
            status = "доступен"
        } else {
            status = "заблокирован"
        }
        var line = "[\(index)] \(step.quest.id) — \(step.quest.title)"
        line += " | requires: " + (index == 0 ? "(старт)" : QuestManager.questChain[index - 1].quest.id)
        line += " | статус: \(status)"
        line += " | эффект: открывает \(step.unlocksSiteID)"
        if !step.announcementSubject.isEmpty {
            line += ", объявление «\(step.announcementSubject)»"
        }
        return stat(step.quest.id, line)
    }

    // MARK: - Вкладка «Журнал»

    private var logTab: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Фильтр по категории…", text: $logFilter)
                    .textFieldStyle(.roundedBorder)
                Spacer()
                Button("Очистить журнал") { logger.clear() }
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        let filtered = filteredLog
                        if filtered.isEmpty {
                            Text("(пусто)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(4)
                        } else {
                            ForEach(Array(filtered.enumerated()), id: \.offset) { offset, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 12)
                                    .id(offset)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: logger.entries.count) { _ in
                    if let last = filteredLog.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var filteredLog: [String] {
        let needle = logFilter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return logger.entries }
        return logger.entries.filter { $0.lowercased().contains(needle) }
    }

    // MARK: - Helpers

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        Section {
            content()
        } header: {
            Text(title)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label + ":")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 190, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
    }

    private func performReset() {
        GameProgressReset.perform(
            game: game,
            quests: quests,
            clock: clock,
            scheduler: scheduler,
            sites: sites,
            catalog: catalog,
            questGenerator: questGenerator,
            fileQuestTracker: fileQuestTracker,
            loveQuestTracker: loveQuestTracker,
            webmasterQuestTracker: webmasterQuestTracker,
            fileStore: fileStore
        )
        DebugLogger.shared.log("Debug", "прогресс сброшен оператором")
    }
}
#endif
