import Foundation

/// Единая точка доступа к пользовательским файлам в локальных папках
/// (downloads/documents/pictures). Все операции идут поверх FileStore —
/// реального доступа к диску нет. Узлы папок имеют вид "local:<имя>",
/// legacy-узел загрузок "downloads" читается как та же папка .downloads.
@MainActor
final class LocalFileStore: ObservableObject {
    private let fileStore: FileStore
    private let bus: GameBus

    init(fileStore: FileStore, bus: GameBus) {
        self.fileStore = fileStore
        self.bus = bus
    }

    /// Файлы одной папки (вместе с legacy-узлом "downloads" для загрузок),
    /// старые сверху.
    func files(in folder: LocalFolder) -> [FileInstance] {
        let instances = folder.matchingNodes.flatMap {
            fileStore.instances(inNode: $0)
        }
        var byId: [String: FileInstance] = [:]
        for instance in instances { byId[instance.instanceId] = instance }
        return byId.values
            .sorted { $0.content.downloadedAt > $1.content.downloadedAt }
    }

    /// Все файлы во всех локальных папках.
    func allFiles() -> [FileInstance] {
        LocalFolder.allCases.flatMap { files(in: $0) }
    }

    /// Переносит файл из одной папки в другую (узел меняется на
    /// локальный узел целевой папки). Возвращает перемещённую копию.
    @discardableResult
    func move(instanceId: String, to folder: LocalFolder) -> FileInstance? {
        fileStore.move(instanceId: instanceId, toNode: folder.ownerNode)
    }

    /// Удаляет файл из Store (публикует `.fileRemoved`).
    @discardableResult
    func remove(instanceId: String) -> Bool {
        fileStore.remove(instanceId: instanceId)
    }

    /// Все безопасные для вложения файлы (без вирусов) в выбранных папках,
    /// сгруппированные по папкам и отсортированные по дате создания (новые сверху).
    func attachableFiles(in folders: [LocalFolder]) -> [FileInstance] {
        folders.flatMap { folder in
            files(in: folder)
                .sorted { $0.createdAt > $1.createdAt }
                .filter { !$0.content.hasVirus }
        }
    }

    /// Все безопасные для вложения файлы (без вирусов) во всех папках.
    func attachableFiles() -> [FileInstance] {
        attachableFiles(in: LocalFolder.allCases)
    }
}