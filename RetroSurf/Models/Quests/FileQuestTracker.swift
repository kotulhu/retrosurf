import Foundation

// MARK: - Definitions (Resources/Quests/file_quests.json)

/// Requirements a quest's start is gated on.
struct QuestRequires: Codable, Sendable {
    let flags: [String]
    let notFlags: [String]

    init(flags: [String] = [], notFlags: [String] = []) {
        self.flags = flags
        self.notFlags = notFlags
    }
}

struct FileQuestDefinition: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let requires: QuestRequires
    /// Range in minutes for the random delay before the request letters go out.
    let delayMinutes: [Double]
    let parts: [FileQuestPart]
    let reward: FileQuestReward
}

struct FileQuestPart: Codable, Sendable {
    let id: String
    let npcId: String
    let targetFileId: String
    let requestSubject: String
    let requestBodyHTML: String
    let thanksSubject: String
    let thanksBodyHTML: String
    let reminderDelaysMinutes: [Double]
    let reminderSubject: String
    let reminderBodyHTML: String
    let completionFlag: String
}

struct FileQuestReward: Codable, Sendable {
    let flag: String
    let artifact: String?
    let reputation: Int?
    let congratulationFrom: String
    let congratulationSubject: String
    let congratulationBodyHTML: String
}

struct FileQuestCatalog: Codable, Sendable {
    let quests: [FileQuestDefinition]

    static func loadFromBundle(named name: String = "file_quests") -> FileQuestCatalog {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("[FileQuestTracker] failed to load \(name).json from bundle")
            return FileQuestCatalog(quests: [])
        }
        do {
            return try JSONDecoder().decode(FileQuestCatalog.self, from: data)
        } catch {
            print("[FileQuestTracker] decode error for \(name).json: \(error)")
            return FileQuestCatalog(quests: [])
        }
    }
}

// MARK: - Runtime state

struct FileQuestPartState: Sendable {
    var completed = false
    /// True once the player sent SOMETHING to the NPC, even if it wasn't the
    /// right file — used to avoid nagging before the first attempt.
    var attempted = false
    var reminderDueAt: Date?
    var reminderCount = 0
}

/// The "Три файла" quest. A quest starts by itself once its requires-flags are
/// satisfied (listening to `.flagChanged`): request letters go out after a
/// random delay. A part completes ONLY when the NPC receives the correct
/// attachment by mail — downloading alone does not count. Wrong or missing
/// attachments schedule reminders (max 3 per part); reminders list the missing
/// files dynamically via {{missing.files}}. Everything is driven by typed
/// GameBus events, never by NotificationCenter.
@MainActor
final class FileQuestTracker: ObservableObject {
    private let quests: [FileQuestDefinition]
    private let mailSite: MailSite
    private let npcCatalog: NpcCatalog
    private let flags: FlagStore
    private let bus: GameBus
    private let fileStore: FileStore

    private var subscriptionID: UUID?
    private var task: Task<Void, Never>?

    private var partStates: [String: FileQuestPartState] = [:]
    private var runStates: [String: QuestRunState] = [:]
    /// Quests whose request letters have gone out (their part letters are
    /// live and completable).
    private var started: Set<String> = []
    private var rewardGiven: Set<String> = []
    private var downloadedContentIds: Set<String> = []

    private struct QuestRunState {
        var scheduledAt: Date?
    }

    /// Fallback file names for known quest targets (used when no downloaded
    /// instance exists yet — e.g. listing a missing file we haven't seen).
    private static let staticFileNames: [String: String] = [
        "music_zemfira": "zemfira_iskala.mp3",
        "drv_modem_us": "us_robotics_56k_driver.zip",
        "wall_cat": "cat_on_keyboard.jpg"
    ]

    init(
        quests: [FileQuestDefinition],
        mailSite: MailSite,
        npcCatalog: NpcCatalog,
        flags: FlagStore,
        bus: GameBus,
        fileStore: FileStore
    ) {
        self.quests = quests
        self.mailSite = mailSite
        self.npcCatalog = npcCatalog
        self.flags = flags
        self.bus = bus
        self.fileStore = fileStore
    }

    // MARK: - Lifecycle

    func start() {
        guard subscriptionID == nil else { return }
        subscriptionID = bus.subscribe { [weak self] event in
            self?.handle(event)
        }
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.tickOnce()
            }
        }
    }

    func stop() {
        if let id = subscriptionID {
            bus.unsubscribe(id)
            subscriptionID = nil
        }
        task?.cancel()
        task = nil
    }

    // MARK: - Bus handling

    private func handle(_ event: GameBus.Event) {
        switch event {
        case .mailSent(let mail):
            handleMailSent(mail)
        case .fileDownloaded(let download):
            downloadedContentIds.insert(download.contentId)
        case .flagChanged:
            // Requirements flip -> give quests a chance to schedule their start.
            let now = Date()
            for quest in quests {
                advanceQuestStart(quest, now: now)
            }
        case .mailReceived, .fileAttached, .fileSent, .fileReceived, .fileRemoved,
             .artifactEarned, .loveMessageSent, .loveMessageDelivered,
             .bytesTransferred, .bytesDownloaded:
            break
        }
    }

    /// Periodic check; fires request letter delivery and due reminders
    /// (kept as a safety net on top of the event-driven `.flagChanged` start).
    func tickOnce(now: Date = Date()) {
        for quest in quests {
            advanceQuestStart(quest, now: now)
            guard started.contains(quest.id) else { continue }
            for part in quest.parts {
                advanceReminder(quest: quest, part: part, now: now)
            }
        }
    }

    /// Schedules/executes the delayed issuance of a quest's request letters.
    private func advanceQuestStart(_ quest: FileQuestDefinition, now: Date) {
        guard !started.contains(quest.id) else { return }
        var run = runStates[quest.id] ?? QuestRunState()
        guard requiresSatisfied(quest) else {
            run.scheduledAt = nil
            runStates[quest.id] = run
            return
        }
        if run.scheduledAt == nil {
            run.scheduledAt = now.addingTimeInterval(pickDelay(quest.delayMinutes))
            runStates[quest.id] = run
            return
        }
        guard let scheduled = run.scheduledAt, scheduled <= now else { return }
        issueRequestLetters(quest)
        started.insert(quest.id)
        run.scheduledAt = nil
        runStates[quest.id] = run
    }

    private func advanceReminder(quest: FileQuestDefinition, part: FileQuestPart, now: Date) {
        var state = partStates[key(for: quest, part: part)] ?? FileQuestPartState()
        guard !state.completed, let dueAt = state.reminderDueAt, dueAt <= now else { return }
        guard state.reminderCount < 3 else {
            state.reminderDueAt = nil
            partStates[key(for: quest, part: part)] = state
            return
        }
        deliverReminder(quest: quest, part: part)
        state.reminderCount += 1
        state.reminderDueAt = state.reminderCount >= 3
            ? nil
            : now.addingTimeInterval(pickDelay(part.reminderDelaysMinutes))
        partStates[key(for: quest, part: part)] = state
    }

    // MARK: - Events: mail sent / file downloaded

    private func handleMailSent(_ mail: MailSentEvent) {
        let to = mail.to.trimmingCharacters(in: .whitespaces).lowercased()
        guard !to.isEmpty else { return }
        let now = mail.sentAt
        for quest in quests where started.contains(quest.id) {
            for part in quest.parts {
                guard emailOf(part: part)?.lowercased() == to else { continue }
                let key = key(for: quest, part: part)
                var state = partStates[key] ?? FileQuestPartState()
                guard !state.completed else { continue }
                if mail.attachmentContentIds.contains(part.targetFileId) {
                    state.completed = true
                    state.attempted = true
                    state.reminderDueAt = nil
                    state.reminderCount = 0
                    partStates[key] = state
                    flags.set(part.completionFlag, to: true)
                    deliverThanks(quest: quest, part: part)
                } else {
                    state.attempted = true
                    if state.reminderDueAt == nil {
                        state.reminderDueAt = now.addingTimeInterval(pickDelay(part.reminderDelaysMinutes))
                    }
                    partStates[key] = state
                }
            }
            if questCompleted(quest) {
                rewardIfNeeded(quest)
            }
        }
    }

    // MARK: - Requests / letters

    private func issueRequestLetters(_ quest: FileQuestDefinition) {
        for part in quest.parts {
            guard let npc = npcCatalog.npc(withId: part.npcId) else {
                print("[FileQuestTracker] unknown npc \(part.npcId) in quest \(quest.id)")
                continue
            }
            deliver(
                from: senderString(npc),
                subject: template(part.requestSubject, quest: quest, part: part),
                body: template(part.requestBodyHTML, quest: quest, part: part),
                tag: "quest.\(quest.id).\(part.id).request"
            )
        }
        print("[FileQuestTracker] issued request letters for quest \(quest.id)")
    }

    private func deliverReminder(quest: FileQuestDefinition, part: FileQuestPart) {
        guard let npc = npcCatalog.npc(withId: part.npcId) else { return }
        let body = template(part.reminderBodyHTML, quest: quest, part: part)
            .replacingOccurrences(of: "{{missing.files}}", with: missingFilesString(for: quest))
        deliver(
            from: senderString(npc),
            subject: template(part.reminderSubject, quest: quest, part: part),
            body: body,
            tag: "quest.\(quest.id).\(part.id).reminder"
        )
        print("[FileQuestTracker] reminder \(quest.id)/\(part.id) → \(npc.email)")
    }

    private func deliverThanks(quest: FileQuestDefinition, part: FileQuestPart) {
        guard let npc = npcCatalog.npc(withId: part.npcId) else { return }
        deliver(
            from: senderString(npc),
            subject: template(part.thanksSubject, quest: quest, part: part),
            body: template(part.thanksBodyHTML, quest: quest, part: part),
            tag: "quest.\(quest.id).\(part.id).thanks"
        )
        print("[FileQuestTracker] thanks \(quest.id)/\(part.id) → \(npc.email)")
    }

    private func rewardIfNeeded(_ quest: FileQuestDefinition) {
        guard !rewardGiven.contains(quest.id) else { return }
        rewardGiven.insert(quest.id)
        flags.set(quest.reward.flag, to: true)
        if let artifact = quest.reward.artifact {
            bus.publish(.artifactEarned(ArtifactEarnedEvent(artifactId: artifact)))
        }
        if let reputation = quest.reward.reputation, reputation > 0 {
            print("[FileQuestTracker] reward \(quest.id): +\(reputation) reputation")
        }
        let sender = npcCatalog.npc(withId: quest.reward.congratulationFrom)
            .map(senderString) ?? quest.reward.congratulationFrom
        deliver(
            from: sender,
            subject: template(quest.reward.congratulationSubject, quest: quest, part: nil),
            body: template(quest.reward.congratulationBodyHTML, quest: quest, part: nil),
            tag: nil
        )
        print("[FileQuestTracker] reward \(quest.id) → flag \(quest.reward.flag)")
    }

    /// Send one letter through MailSite; from is NPC-facing, the inbox is
    /// always the player's. Letters are tagged with the quest part they belong
    /// to so the UI/bus can attribute them.
    @discardableResult
    private func deliver(from: String, subject: String, body: String, tag: String?) -> Int {
        mailSite.deliver(
            MailDraft(
                from: from,
                subject: subject,
                bodyHTML: body,
                tag: tag,
                timestamp: Date(),
                folder: .inbox
            )
        )
    }

    private func template(_ text: String, quest: FileQuestDefinition, part: FileQuestPart?) -> String {
        var result = text
        result = result.replacingOccurrences(of: "{{player.username}}", with: mailSite.currentUsername ?? "Ты")
        if let part {
            let npcName = npcCatalog.npc(withId: part.npcId)?.displayName ?? ""
            result = result.replacingOccurrences(of: "{{npc.name}}", with: npcName)
        }
        return result
    }

    // MARK: - Missing files

    /// Comma-separated list of file names for the quest parts that still need
    /// their target file — the {{missing.files}} placeholder content.
    private func missingFilesString(for quest: FileQuestDefinition) -> String {
        quest.parts
            .filter { !(partStates[key(for: quest, part: $0)]?.completed ?? false) }
            .compactMap { fileName(forContentId: $0.targetFileId) }
            .joined(separator: ", ")
    }

    /// Best-known download name for a content id: a downloaded instance wins,
    /// then the static table of known quest files.
    private func fileName(forContentId contentId: String) -> String? {
        if let instance = fileStore.instances(withContentId: contentId).first {
            return instance.content.name
        }
        return Self.staticFileNames[contentId]
    }

    // MARK: - Debug / test helpers

    /// Delivers the request letters for a quest immediately, regardless of
    /// requires/delay. Returns false when the quest id is unknown or already
    /// started.
    @discardableResult
    func forceStart(_ questId: String) -> Bool {
        guard let quest = quests.first(where: { $0.id == questId }) else {
            print("[FileQuestTracker] forceStart: unknown quest \(questId)")
            return false
        }
        guard !started.contains(questId) else { return false }
        issueRequestLetters(quest)
        started.insert(questId)
        runStates[questId] = QuestRunState()
        return true
    }

    /// For testing: publishes a download event (does NOT complete anything).
    /// Returns the part ids this download concerns.
    @discardableResult
    func simulateDownload(contentId: String) -> [String] {
        let instanceId = "sim:\(String(UUID().uuidString.prefix(8)))"
        bus.publish(.fileDownloaded(
            FileDownloadedEvent(
                contentId: contentId,
                instanceId: instanceId,
                name: contentId,
                sizeBytes: 1,
                hasVirus: false,
                downloadedAt: Date()
            )
        ))
        return partIDs(forContentId: contentId)
    }

    /// For testing: publishes a send event with a single attachment, as if the
    /// player mailed the file. Returns the part ids this send concerns.
    @discardableResult
    func simulateSend(contentId: String, to: String) -> [String] {
        let messageId = Int.random(in: 100_000...999_999)
        bus.publish(.mailSent(
            MailSentEvent(
                messageId: messageId,
                to: to,
                subject: "sim",
                attachmentContentIds: [contentId],
                tag: nil,
                sentAt: Date()
            )
        ))
        return partIDs(forContentId: contentId)
    }

    // MARK: - Reset

    func reset() {
        stop()
        partStates = [:]
        runStates = [:]
        started = []
        rewardGiven = []
        downloadedContentIds = []
        start()
    }

    // MARK: - Helpers

    private func key(for quest: FileQuestDefinition, part: FileQuestPart) -> String {
        "\(quest.id).\(part.id)"
    }

    private func partIDs(forContentId contentId: String) -> [String] {
        var result: [String] = []
        for quest in quests {
            for part in quest.parts where part.targetFileId == contentId {
                result.append(key(for: quest, part: part))
            }
        }
        return result
    }

    private func emailOf(part: FileQuestPart) -> String? {
        npcCatalog.npc(withId: part.npcId)?.email
    }

    private func senderString(_ npc: NpcProfile) -> String {
        "\(npc.displayName) <\(npc.email)>"
    }

    private func requiresSatisfied(_ quest: FileQuestDefinition) -> Bool {
        quest.requires.flags.allSatisfy { flags.contains($0) }
            && quest.requires.notFlags.allSatisfy { !flags.contains($0) }
    }

    private func questCompleted(_ quest: FileQuestDefinition) -> Bool {
        quest.parts.allSatisfy { partStates[key(for: quest, part: $0)]?.completed == true }
    }

    /// Random delay in seconds from a [min, max] minutes range.
    private func pickDelay(_ minutes: [Double]) -> TimeInterval {
        guard let lo = minutes.min(), let hi = minutes.max(), hi > 0 else {
            return 60
        }
        return Double.random(in: max(0.01, lo)...hi) * 60
    }
}