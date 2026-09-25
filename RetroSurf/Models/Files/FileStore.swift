import Foundation

/// The instance graph for all files in the simulated network. Files are
/// copied between named nodes by the mailbox/quest systems; the filesystem is
/// never touched. Events are only published by the operations that DELETE a
/// copy (.fileRemoved) — creation is the caller's responsibility.
///
/// The graph survives app relaunches: every mutation is archived to
/// UserDefaults and restored in `init`. That is what keeps finished downloads
/// in the «Мои документы/Загрузки» folder independent of the app restarting.
@MainActor
final class FileStore: ObservableObject {
    @Published private(set) var instances: [FileInstance] = []

    /// UserDefaults key holding the archived instance graph across launches.
    static let instancesDefaultsKey = "FileStore.instances"

    private let bus: GameBus

    init(bus: GameBus) {
        self.bus = bus
        if let data = UserDefaults.standard.data(forKey: Self.instancesDefaultsKey),
           let restored = try? JSONDecoder().decode([FileInstance].self, from: data) {
            instances = restored
        }
    }

    /// Creates a new instance in `ownerNode`. The instanceId is
    /// "{ownerNode}:{uuid-prefix}" (e.g. "downloads:7f3a9b2c"), which makes
    /// nodes readable at a glance. A single content may exist in many nodes
    /// and many times — no deduplication happens here.
    @discardableResult
    func create(content: FileContent, ownerNode: String) -> FileInstance {
        let prefix = String(UUID().uuidString.prefix(8))
        let instance = FileInstance(
            instanceId: "\(ownerNode):\(prefix)",
            content: content,
            createdAt: Date(),
            ownerNode: ownerNode
        )
        instances.append(instance)
        save()
        return instance
    }

    func instance(withId instanceId: String) -> FileInstance? {
        instances.first { $0.instanceId == instanceId }
    }

    func instances(inNode node: String) -> [FileInstance] {
        instances.filter { $0.ownerNode == node }
    }

    func instances(withContentId contentId: String) -> [FileInstance] {
        instances.filter { $0.content.contentId == contentId }
    }

    /// Removes the instance and publishes `.fileRemoved`. Returns true when
    /// the instance existed; never throws for a missing id.
    @discardableResult
    func remove(instanceId: String) -> Bool {
        guard let index = instances.firstIndex(where: { $0.instanceId == instanceId }) else {
            return false
        }
        let removed = instances.remove(at: index)
        save()
        bus.publish(.fileRemoved(
            FileRemovedEvent(
                contentId: removed.content.contentId,
                instanceId: removed.instanceId,
                ownerNode: removed.ownerNode
            )
        ))
        return true
    }

    /// Move = remove + create in the new node. Publishes no event (the caller
    /// decides what the move means — e.g. `.fileSent`). Returns the new
    /// instance, or nil when the source does not exist.
    @discardableResult
    func move(instanceId: String, toNode newOwner: String) -> FileInstance? {
        guard let index = instances.firstIndex(where: { $0.instanceId == instanceId }) else {
            return nil
        }
        let source = instances.remove(at: index)
        return create(content: source.content, ownerNode: newOwner)
    }

    /// Wipes the whole graph (all local folders, mailbox, drafts). Used by a
    /// full gameplay reset so downloads do not outlive a fresh start.
    func clearAll() {
        instances = []
        UserDefaults.standard.removeObject(forKey: Self.instancesDefaultsKey)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(instances) {
            UserDefaults.standard.set(data, forKey: Self.instancesDefaultsKey)
        }
    }
}