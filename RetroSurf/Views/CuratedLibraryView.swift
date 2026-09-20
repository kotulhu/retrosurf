import SwiftUI

struct CuratedLibraryView: View {
    @EnvironmentObject private var catalog: SiteCatalog
    @Environment(\.dismiss) private var dismiss

    @State private var editingID: String?
    @State private var draftTitle = ""
    @State private var deleteTarget: SiteEntry?

    private var curatedEntries: [SiteEntry] {
        catalog.entries.filter { $0.isUserAdded }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Мои сохранённые сайты")
                .font(.system(size: 15, weight: .bold))

            if curatedEntries.isEmpty {
                Text("Пока нет сохранённых сайтов. Добавьте сайт через «Добавить сайт…» в тулбаре.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(curatedEntries) { entry in
                            entryRow(entry)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Закрыть") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 440)
        .alert(
            "Удалить сайт?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            presenting: deleteTarget
        ) { entry in
            Button("Удалить", role: .destructive) {
                try? catalog.removeCuratedEntry(id: entry.id)
            }
            Button("Отмена", role: .cancel) {
                deleteTarget = nil
            }
        } message: { entry in
            Text("«\(entry.title)» будет удалён вместе с сохранёнными файлами.")
        }
    }

    private func entryRow(_ entry: SiteEntry) -> some View {
        HStack(alignment: .center, spacing: 10) {
            if editingID == entry.id {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Название", text: $draftTitle)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 8) {
                        Button("Сохранить") {
                            let cleaned = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !cleaned.isEmpty {
                                try? catalog.updateCuratedEntry(id: entry.id, newTitle: cleaned)
                            }
                            editingID = nil
                        }
                        .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Отмена") {
                            editingID = nil
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(entry.displayDomain)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Изменить") {
                    editingID = entry.id
                    draftTitle = entry.title
                }
                .controlSize(.small)
                Button(role: .destructive) {
                    deleteTarget = entry
                } label: {
                    Text("Удалить")
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}