import Foundation
import SwiftUI

struct Quest: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let targetSiteID: String
}

struct QuestStep {
    let quest: Quest
    let unlocksSiteID: String
    let announcementSubject: String
    let announcementBody: String
    let announcementFrom: String
}

@MainActor
final class QuestManager: ObservableObject {
    @Published private(set) var completedQuestIDs: Set<String> = []

    static let registrationQuestID = "quest_pochta"
    static let homepageQuestID = "quest_homepage"

    static let questChain: [QuestStep] = [
        QuestStep(
            quest: Quest(
                id: "quest_pochta",
                title: "Заведи почту",
                description: "Зарегистрируй бесплатный электронный ящик на pochta.su",
                targetSiteID: "pochta-su"
            ),
            unlocksSiteID: "pochta-su",
            announcementSubject: "",
            announcementBody: "",
            announcementFrom: ""
        ),
        QuestStep(
            quest: Quest(
                id: "quest_homepage",
                title: "Заведи свою страничку",
                description: "Создай свою домашнюю страничку на бесплатном хостинге",
                targetSiteID: "homepage-su"
            ),
            unlocksSiteID: "homepage-su",
            announcementSubject: "Заведи свою домашнюю страничку!",
            announcementBody: "Привет! Теперь, когда у тебя есть почта, самое время сделать свою собственную страничку в интернете. Переходи на {homepage-su} и попробуй!",
            announcementFrom: "Subscribe.ru"
        ),
        QuestStep(
            quest: Quest(
                id: "quest_znakomstva",
                title: "Зарегистрируйся на сайте знакомств",
                description: "Создай анкету и найди собеседника на сайте знакомств",
                targetSiteID: "znakomstva-su"
            ),
            unlocksSiteID: "znakomstva-su",
            announcementSubject: "Не хочешь познакомиться с кем-нибудь?",
            announcementBody: "Заскучал? На {znakomstva-su} тебя уже ждут!",
            announcementFrom: "Subscribe.ru"
        )
    ]

    private let mailSite: MailSite
    private let messageScheduler: MessageScheduler

    private enum Keys {
        static let completed = "QuestManager.completedQuestIDs"
    }

    init(mailSite: MailSite, messageScheduler: MessageScheduler) {
        self.mailSite = mailSite
        self.messageScheduler = messageScheduler
        guard let data = UserDefaults.standard.data(forKey: Keys.completed),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return
        }
        completedQuestIDs = Set(decoded)
    }

    var allQuests: [Quest] {
        Self.questChain.map(\.quest)
    }

    func quest(id: String) -> Quest? {
        allQuests.first { $0.id == id }
    }

    func isCompleted(_ questID: String) -> Bool {
        completedQuestIDs.contains(questID)
    }

    func markCompleted(_ questID: String) {
        guard !completedQuestIDs.contains(questID) else { return }
        completedQuestIDs.insert(questID)
        persist()
#if DEBUG
        DebugLogger.shared.log("Quest", "completed '\(questID)' (\(quest(id: questID)?.title ?? ""))")
#endif
        deliverAnnouncement(forNextStepAfter: questID)
        if questID == Self.registrationQuestID {
            deliverAtmosphereMail()
        }
    }

    /// Clears all completed quests (used by the debug progress reset).
    func resetCompleted() {
        completedQuestIDs.removeAll()
        persist()
    }

    func hasCompletedQuestFor(siteID: String) -> Bool {
        completedQuestIDs.contains { questID in
            quest(id: questID)?.targetSiteID == siteID
        }
    }

    func questID(forSiteID siteID: String) -> String? {
        allQuests.first { $0.targetSiteID == siteID }?.id
    }

    private func deliverAnnouncement(forNextStepAfter questID: String) {
        guard let index = Self.questChain.firstIndex(where: { $0.quest.id == questID }),
              index + 1 < Self.questChain.count else { return }
        let step = Self.questChain[index + 1]
        guard !step.announcementSubject.isEmpty else { return }
        let sender = Sender(
            archetypeId: "service",
            name: SenderName(full: step.announcementFrom, firstName: step.announcementFrom, login: "subscribe"),
            address: "subscribe@subscribe.ru",
            kind: .service,
            gender: .none
        )
        messageScheduler.schedule(
            channel: .mail,
            targetSiteId: "mail",
            message: QuestMessage(
                questID: "announcement.\(step.quest.id)",
                sender: sender,
                subject: step.announcementSubject,
                bodyHTML: step.announcementBody,
                tag: nil,
                messageCategory: "questAnnouncement",
                relatedSiteId: step.unlocksSiteID,
                timestamp: Date()
            )
        )
    }

    private func deliverAtmosphereMail() {
        let mails: [(from: String, subject: String, body: String)] = [
            (
                "Лотерея «Миллион»",
                "ВЫ ПОБЕДИТЕЛЬ!!! Заберите приз",
                "Уважаемый пользователь! Поздравляем: именно ваш адрес выбран победителем розыгрыша! Чтобы получить приз, отправьте СМС со словом PRIZ на номер 5555. Только сегодня!"
            ),
            (
                "Новости Рунета",
                "Дайджест недели: почта, чаты и погода",
                "В этом выпуске: как купить пиццу, не выходя из дома; обзор самых модных чатов; и почему все переходят на ADSL. Подробности на нашем сайте!"
            )
        ]
        for mail in mails {
            let bodyHTML = "<p>\(MailTemplates.escapeHTML(mail.body))</p>"
            mailSite.deliver(
                MailDraft(
                    from: mail.from,
                    subject: mail.subject,
                    bodyHTML: bodyHTML,
                    tag: nil,
                    timestamp: Date(),
                    folder: .inbox
                )
            )
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Array(completedQuestIDs).sorted()) {
            UserDefaults.standard.set(data, forKey: Keys.completed)
        }
        UserDefaults.standard.synchronize()
    }
}
