import Combine
import Foundation

/// The game's artifact ledger: every named artifact the player earns, the
/// points they grant, and whether the final «последняя страница» is unlocked.
/// In-memory only — nothing here is persisted across launches.
@MainActor
final class ProgressStore: ObservableObject {
    /// Every artifact grants the same fixed points.
    static let pointsPerArtifact = 20
    /// Points needed for the lastpage.su world to unlock.
    static let thresholdPoints = 60

    /// Fixed display order of the collection, «Коллекция» first.
    static let artifactSlots: [ArtifactSlot] = [
        ArtifactSlot(artifactId: "artifact.collection", title: "Коллекция", subtitle: "Файлы для куратора"),
        ArtifactSlot(artifactId: "artifact.page", title: "Личная страничка", subtitle: "Свой уголок в сети"),
        ArtifactSlot(artifactId: "artifact.love", title: "Любовь", subtitle: "Переписка с симпатией")
    ]

    private let bus: GameBus
    private var subscriptionID: UUID?
    private var cancellables: Set<AnyCancellable> = []

    /// Earned artifact ids. Repeated earnings are idempotent no-ops.
    @Published private(set) var artifacts: Set<String> = []

    init(bus: GameBus) {
        self.bus = bus
        subscriptionID = bus.subscribe { [weak self] event in
            self?.handle(event)
        }
        // A hard progress reset (debug operator) wipes the artifacts too, so
        // the collection has to be re-earned.
        NotificationCenter.default.publisher(for: .gameProgressDidReset)
            .sink { [weak self] _ in self?.reset() }
            .store(in: &cancellables)
    }

    deinit {
        if let id = subscriptionID {
            Task { @MainActor [bus] in
                bus.unsubscribe(id)
            }
        }
    }

    private func handle(_ event: GameBus.Event) {
        if case .artifactEarned(let payload) = event {
            earn(payload.artifactId)
        }
    }

    /// Marks an artifact as earned. Never crashes on unknown ids
    /// (the id is stored as-is; if it has no display slot it still
    /// contributes points).
    @discardableResult
    func earn(_ artifactId: String) -> Bool {
        guard !artifacts.contains(artifactId) else { return false }
        artifacts.insert(artifactId)
        return true
    }

    /// Wipes the earned set (used by the debug operator / progress reset).
    func reset() {
        artifacts.removeAll()
    }

    var points: Int {
        artifacts.count * Self.pointsPerArtifact
    }

    /// Progress toward the unlock threshold, 0...100.
    var percent: Int {
        min(100, points * 100 / Self.thresholdPoints)
    }

    /// Grants access to the final site once enough artifacts are collected.
    var isFinalUnlocked: Bool {
        points >= Self.thresholdPoints
    }

    /// True when the given artifact has been earned.
    func has(_ artifactId: String) -> Bool {
        artifacts.contains(artifactId)
    }
}

/// A named collectible displayed on the start page progress block.
struct ArtifactSlot: Identifiable, Sendable {
    let artifactId: String
    let title: String
    let subtitle: String

    var id: String { artifactId }
}