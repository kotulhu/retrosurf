import SwiftUI

/// Modal shown when MailSite asks the browser to pick attachments for the
/// compose form. Files come from the two attachable folders (downloads,
/// documents — grouped into two sections); the player picks a set from any
/// folder, then confirms («Прикрепить») or cancels. Cancelling just reloads
/// the compose page — nothing has been mutated yet.
struct AttachmentPickerView: View {
    let files: [FileInstance]
    let onConfirm: ([FileInstance]) -> Void
    let onCancel: () -> Void

    @State private var selectedContentIDs: Set<String> = []

    private let columns: [GridItem] = [
        GridItem(.flexible(), alignment: .leading),
        GridItem(.fixed(90), alignment: .trailing),
        GridItem(.fixed(120), alignment: .leading)
    ]

    /// Files grouped into the two sections, in a fixed order
    /// (Загрузки, Документы). Empty sections are still present so the
    /// "нет файлов" hint is shown per section.
    private var groupedFiles: [(folder: LocalFolder, files: [FileInstance])] {
        [LocalFolder.downloads, LocalFolder.documents].map { folder in
            let list = files.filter {
                LocalFolder.folder(forOwnerNode: $0.ownerNode) == folder
            }
            return (folder, list)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Прикрепить файл")
                .font(.headline)
            if files.isEmpty {
                Text("Нет локальных файлов. Сначала скачайте файл с Files.su.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(groupedFiles, id: \.folder.id) { group in
                            folderSection(group.folder, files: group.files)
                        }
                    }
                }
                .frame(minHeight: 180, maxHeight: 320)
            }
            HStack {
                Spacer()
                Button("Отмена") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button(files.isEmpty ? "Готово" : "Прикрепить (\(selectedContentIDs.count))") {
                    onConfirm(files.filter { selectedContentIDs.contains($0.content.contentId) })
                }
                .keyboardShortcut(.defaultAction)
                .disabled(files.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 260)
    }

    private func folderSection(_ folder: LocalFolder, files: [FileInstance]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(folder.displayName)
                .font(.subheadline).fontWeight(.bold)
                .foregroundStyle(.secondary)
            if files.isEmpty {
                Text("В этой папке нет файлов.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Файл").fontWeight(.bold)
                        Text("Размер").fontWeight(.bold)
                        Text("Дата").fontWeight(.bold)
                    }
                    ForEach(files) { file in
                        fileRow(for: file)
                    }
                }
                .font(.callout)
            }
        }
    }

    private func fileRow(for file: FileInstance) -> some View {
        let isSelected = selectedContentIDs.contains(file.content.contentId)
        let selectionIcon = isSelected ? "checkmark.square" : "square"
        return GridRow {
            HStack(spacing: 6) {
                Image(systemName: selectionIcon)
                Text(file.content.name).lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture { toggle(file) }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            Text(FileSizeFormatter.format(file.content.sizeBytes))
            Text(file.createdAt.formatted(date: .abbreviated, time: .shortened))
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle(file) }
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private func toggle(_ file: FileInstance) {
        let contentId = file.content.contentId
        if selectedContentIDs.contains(contentId) {
            selectedContentIDs.remove(contentId)
        } else {
            selectedContentIDs.insert(contentId)
        }
    }
}