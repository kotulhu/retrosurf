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

    private let mailbox: MailboxManager

    private enum Keys {
        static let completed = "QuestManager.completedQuestIDs"
    }

    init(mailbox: MailboxManager) {
        self.mailbox = mailbox
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
        deliverAnnouncement(forNextStepAfter: questID)
        if questID == Self.registrationQuestID {
            deliverAtmosphereMail()
        }
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
        mailbox.deliver(
            MailMessage(
                id: UUID().uuidString,
                from: step.announcementFrom,
                subject: step.announcementSubject,
                body: step.announcementBody,
                date: Date(),
                isRead: false,
                relatedSiteID: step.unlocksSiteID,
                category: .questAnnouncement
            )
        )
    }

    private func deliverAtmosphereMail() {
        let mails: [MailMessage] = [
            MailMessage(
                id: UUID().uuidString,
                from: "Лотерея «Миллион»",
                subject: "ВЫ ПОБЕДИТЕЛЬ!!! Заберите приз",
                body: "Уважаемый пользователь! Поздравляем: именно ваш адрес выбран победителем розыгрыша! Чтобы получить приз, отправьте СМС со словом PRIZ на номер 5555. Только сегодня!",
                date: Date(),
                isRead: false,
                relatedSiteID: nil,
                category: .spam
            ),
            MailMessage(
                id: UUID().uuidString,
                from: "Новости Рунета",
                subject: "Дайджест недели: почта, чаты и погода",
                body: "В этом выпуске: как купить пиццу, не выходя из дома; обзор самых модных чатов; и почему все переходят на ADSL. Подробности на нашем сайте!",
                date: Date(),
                isRead: false,
                relatedSiteID: nil,
                category: .newsletter
            )
        ]
        for mail in mails {
            mailbox.deliver(mail)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Array(completedQuestIDs).sorted()) {
            UserDefaults.standard.set(data, forKey: Keys.completed)
        }
        UserDefaults.standard.synchronize()
    }
}