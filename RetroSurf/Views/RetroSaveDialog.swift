import SwiftUI
import AppKit

struct RetroSaveDialog: View {
    let download: SiteDownload
    let onSave: (URL) -> Void
    let onCancel: () -> Void

    @State private var folder = "C:\\Мои документы\\Загрузки"
    @State private var fileName = ""
    @FocusState private var fileNameFocused: Bool

    private let folderPresets: [(label: String, path: String, disabled: Bool)] = [
        ("C:\\Мои документы\\Загрузки", "C:\\Мои документы\\Загрузки", false),
        ("C:\\Мои документы", "C:\\Мои документы", false),
        ("A:\\ (дискета почти полна)", "A:\\", true),
    ]

    var body: some View {
        VStack(spacing: 0) {
            win95TitleBar("Сохранить как")
            content
            buttonsRow
        }
        .frame(width: 460, height: 250)
        .background(w95Face)
        .onAppear(perform: seedFileName)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            folderSection
            fieldset {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Имя файла:")
                        .foregroundColor(w95Black)
                    TextField("", text: $fileName)
                        .textFieldStyle(.plain)
                        .focused($fileNameFocused)
                        .win95Field()
                        .onSubmit(save)
                }
            }
            fieldset {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Тип файла:")
                        .foregroundColor(w95Black)
                    Menu {
                        Text(fileTypeLabel)
                            .disabled(true)
                    } label: {
                        HStack {
                            Text(fileTypeLabel)
                                .foregroundColor(w95Black)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(w95Black)
                        }
                        .win95Field()
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize(horizontal: false, vertical: false)
                    .frame(height: 24)
                }
            }
        }
        .padding(12)
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Папка:")
                .foregroundColor(w95Black)
            menuForFolder
        }
    }

    private var menuForFolder: some View {
        Menu {
            ForEach(folderPresets, id: \.path) { preset in
                Button(preset.label) {
                    folder = preset.path
                }
                .disabled(preset.disabled)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundColor(w95Black)
                Text(folder)
                    .foregroundColor(w95Black)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(w95Black)
            }
            .padding(.horizontal, 6)
            .win95Field()
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: false)
        .frame(height: 24)
    }

    private var buttonsRow: some View {
        HStack {
            Spacer()
            Win95Button("Сохранить", isDefault: true) { save() }
            Win95Button("Отмена", isDefault: false) { onCancel() }
                .keyboardShortcut(.cancelAction)
            Spacer()
        }
        .padding(.bottom, 12)
    }

    private var fileTypeLabel: String {
        switch fileExtension.lowercased() {
        case "exe": return "Программа (*.exe)"
        case "jpg", "jpeg", "bmp", "gif": return "Картинка (*.jpg)"
        case "zip", "rar", "7z": return "Архив (*.zip)"
        case "mp3": return "MP3 (*.mp3)"
        default: return "Файл (*.\(fileExtension.lowercased()))"
        }
    }

    private var fileExtension: String {
        let components = fileName.components(separatedBy: ".")
        guard components.count >= 2, let last = components.last, !last.isEmpty else {
            return "file"
        }
        return last
    }

    private func save() {
        let safeFolder = folder.replacingOccurrences(of: "\\", with: "/")
        let name = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = name.isEmpty ? download.fileName : name
        let target = URL(fileURLWithPath: safeFolder).appendingPathComponent(finalName)
        onSave(target)
    }

    private func seedFileName() {
        fileName = download.fileName
        fileNameFocused = true
    }
}

@MainActor
final class RetroSaveDialogController: ObservableObject {
    @Published var pending: SiteDownload?
    private var onSave: ((URL) -> Void)?

    func present(_ download: SiteDownload, onSave: @escaping (URL) -> Void) {
        self.onSave = onSave
        pending = download
    }

    func accept(url: URL) {
        let handler = onSave
        dismiss()
        handler?(url)
    }

    func cancel() {
        dismiss()
    }

    func dismiss() {
        onSave = nil
        pending = nil
    }
}

// MARK: - Windows 95 chrome

private let w95Face = Color(nsColor: NSColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1))
private let w95Blue = Color(nsColor: NSColor(red: 0.0, green: 0.0, blue: 0.5, alpha: 1))
private let w95Black = Color.black

private struct win95TitleBar: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.leading, 4)
            Spacer()
            Text("✕")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 1)
                        .fill(w95Face)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 1)
                        .stroke(Color.black.opacity(0.6), lineWidth: 1)
                )
                .padding(.trailing, 2)
        }
        .frame(height: 20)
        .padding(.vertical, 2)
        .background(w95Blue)
    }
}

private func fieldset<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content()
        .padding(8)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.black.opacity(0.25), lineWidth: 1)
        )
        .padding(1)
}

/// Thin silver field with the classic bevel: dark top-left, light bottom-right.
private struct Win95FieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 11))
            .foregroundColor(w95Black)
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(Color.white.opacity(0.92))
            .overlay(
                Rectangle()
                    .stroke(
                        LinearGradient(
                            colors: [Color(white: 0.5), Color(white: 0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

private extension View {
    func win95Field() -> some View {
        modifier(Win95FieldModifier())
    }
}

private struct Win95Button: View {
    let title: String
    var isDefault: Bool
    let action: () -> Void

    init(_ title: String, isDefault: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isDefault = isDefault
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isDefault ? .bold : .regular))
                .foregroundColor(w95Black)
                .frame(width: 90, height: 24)
                .background(w95Face)
                .overlay(
                    Rectangle()
                        .stroke(
                            LinearGradient(
                                colors: [Color(white: 0.35), Color.white],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isDefault ? 2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .padding(4)
    }
}