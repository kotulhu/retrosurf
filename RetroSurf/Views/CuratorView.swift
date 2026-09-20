import SwiftUI

struct CuratorView: View {
    @EnvironmentObject private var catalog: SiteCatalog
    @StateObject private var manager = CurationManager()

    @State private var url = ""
    @State private var year = 1999
    @State private var title = ""
    @State private var confirmYear: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Добавление сайта в каталог")
                .font(.system(size: 15, weight: .bold))

            VStack(alignment: .leading, spacing: 10) {
                labeledField("URL") {
                    TextField("например, geocities.com/~someuser", text: $url)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("Год снепшота") {
                    Picker("Год", selection: $year) {
                        ForEach(1994...2005, id: \.self) { value in
                            Text(String(value)).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                }

                labeledField("Название сайта") {
                    TextField("Как сайт будет называться в каталоге", text: $title)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Button {
                start()
            } label: {
                Text(isBusy ? "Выполняется…" : "Скачать и добавить в каталог")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canStart)

            statusArea

            HStack {
                Spacer()
                Button("Закрыть") {
                    manager.cancel()
                    close()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onChange(of: manager.phase) { phase in
            if case .confirming(let alternate) = phase {
                confirmYear = alternate
            }
            if phase == .done {
                catalog.loadAll()
            }
        }
        .alert(
            "Снепшот не найден",
            isPresented: Binding(
                get: { confirmYear != nil },
                set: { if !$0 { confirmYear = nil } }
            ),
            presenting: confirmYear
        ) { alternate in
            Button("Да, использовать \(alternate)") {
                confirmYear = nil
                manager.confirmAlternative()
            }
            Button("Отмена", role: .cancel) {
                confirmYear = nil
                manager.cancel()
            }
        } message: { alternate in
            Text("Для \(year) снепшот не найден. Ближайший доступный: \(alternate). Использовать его?")
        }
    }

    @Environment(\.dismiss) private var dismiss
    private func close() {
        dismiss()
    }

    private func start() {
        manager.start(
            rawURL: url,
            year: year,
            title: title,
            catalog: catalog,
            existingSlugs: Set(catalog.entries.map(\.id))
        )
    }

    private var isBusy: Bool { manager.isBusy }

    private var canStart: Bool {
        !manager.isBusy
            && !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var statusArea: some View {
        if isBusy {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(manager.activity)
                    .font(.system(size: 12))
            }
        } else if case .done = manager.phase {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Готово. Добавлен: \(manager.lastAddedEntry?.title ?? "")")
                    .font(.system(size: 12))
            }
        } else if case .failed(let reason) = manager.phase {
            HStack(spacing: 10) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text(reason)
                    .font(.system(size: 12))
            }
        }
    }

    private func labeledField(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
            content()
        }
    }
}