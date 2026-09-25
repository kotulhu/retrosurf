import SwiftUI
import AppKit

/// «Загрузки» — the download history panel. 90s palette: grey face, silver
/// headers, Verdana 11, thin 1px separators. Rows merge in-flight transfers
/// (progress) with completed FileInstances from the downloads node.
struct DownloadsPanelView: View {
    @ObservedObject var store: DownloadsStore
    let onRedownload: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            headerRow
            Divider().overlay(Color.black.opacity(0.4))
            rowsList
            footer
        }
        .frame(width: 620, height: 340)
        .background(Color(nsColor: NSColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1)))
    }

    private struct PanelRow: Identifiable {
        enum Kind {
            case inProgress(percent: Int)
            case completed
            case cancelled
            case failed
        }

        let id: String
        let fileName: String
        let sizeBytes: Int
        let date: Date
        let kind: Kind
        let hasVirus: Bool
        let contentId: String?
    }

    /// In-flight records plus completed instances, newest first.
    private var mergedRows: [PanelRow] {
        let inProgress = store.inFlight.map { record in
            let percent = record.sizeBytes > 0
                ? Int((Double(record.bytesSent) / Double(record.sizeBytes)) * 100)
                : 0
            let kind: PanelRow.Kind
            switch record.status {
            case .inProgress: kind = .inProgress(percent: percent)
            case .completed: kind = .completed
            case .failed: kind = .failed
            case .cancelled: kind = .cancelled
            }
            return PanelRow(
                id: record.id,
                fileName: record.fileName,
                sizeBytes: record.sizeBytes,
                date: record.startedAt,
                kind: kind,
                hasVirus: record.hasVirus,
                contentId: nil
            )
        }
        let completed = store.completedFiles.map { instance in
            PanelRow(
                id: instance.instanceId,
                fileName: instance.content.name,
                sizeBytes: instance.content.sizeBytes,
                date: instance.content.downloadedAt,
                kind: .completed,
                hasVirus: instance.content.hasVirus,
                contentId: instance.content.contentId
            )
        }
        return (inProgress + completed).sorted { $0.date > $1.date }
    }

    private var titleBar: some View {
        HStack {
            Text("Загрузки")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.leading, 4)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("✕")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 16, height: 16)
                    .background(Color.white.opacity(0.85))
                    .overlay(Rectangle().stroke(Color.black.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 2)
        }
        .frame(height: 22)
        .background(Color(nsColor: NSColor(red: 0, green: 0, blue: 0.5, alpha: 1)))
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            headerCell("Имя файла", width: 190, alignment: .leading)
            headerCell("Размер", width: 70, alignment: .trailing)
            headerCell("Статус", width: 120, alignment: .leading)
            headerCell("Дата", width: 120, alignment: .leading)
            headerCell("", width: 110, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: NSColor(red: 0.83, green: 0.82, blue: 0.78, alpha: 1)))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.4)).frame(height: 1)
        }
    }

    private func headerCell(_ text: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.black)
            .frame(width: width, alignment: alignment)
    }

    private var rowsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                if mergedRows.isEmpty {
                    VStack {
                        Spacer()
                        Text("Скачанных файлов пока нет.")
                            .font(.system(size: 11))
                            .foregroundColor(Color.black.opacity(0.6))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach(mergedRows) { row in
                        rowView(for: row)
                        Divider().overlay(Color.black.opacity(0.15))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rowView(for row: PanelRow) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                if row.hasVirus {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
                Text(row.fileName)
                    .font(.system(size: 11))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: 190, alignment: .leading)

            Text(FileSizeFormatter.format(row.sizeBytes))
                .font(.system(size: 11))
                .foregroundColor(.black)
                .frame(width: 70, alignment: .trailing)

            Text(statusText(for: row))
                .font(.system(size: 11))
                .foregroundColor(statusColor(for: row))
                .frame(width: 120, alignment: .leading)

            Text(Self.dateFormatter.string(from: row.date))
                .font(.system(size: 11))
                .foregroundColor(.black)
                .frame(width: 120, alignment: .leading)

            actions(for: row)
                .frame(width: 110, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func actions(for row: PanelRow) -> some View {
        switch row.kind {
        case .completed:
            HStack(spacing: 8) {
                Button("Открыть папку") {
                    revealInFinder(fileName: row.fileName)
                }
                .buttonStyle(plainLinkStyle)
                Button("Скачать снова") {
                    if let contentId = row.contentId {
                        onRedownload(contentId)
                    }
                }
                .buttonStyle(plainLinkStyle)
            }
        case .inProgress:
            Text("…")
                .font(.system(size: 11))
                .foregroundColor(Color.black.opacity(0.5))
        case .cancelled, .failed:
            Text("")
        }
    }

    /// Reveals the real stub file in Finder when it exists, otherwise opens
    /// the real ~/Downloads folder.
    private func revealInFinder(fileName: String) {
        let url = store.diskURL(for: fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(DownloadsStore.realDownloadsDirectoryURL)
        }
    }

    private func statusText(for row: PanelRow) -> String {
        switch row.kind {
        case .inProgress(let percent):
            return "Загрузка \(min(percent, 100))%"
        case .completed:
            return "Завершено"
        case .cancelled:
            return "Отменено"
        case .failed:
            return "Ошибка"
        }
    }

    private func statusColor(for row: PanelRow) -> Color {
        switch row.kind {
        case .inProgress: return .blue
        case .completed: return Color(red: 0, green: 0.5, blue: 0)
        case .cancelled: return .gray
        case .failed: return .red
        }
    }

    private var footer: some View {
        HStack {
            Button("Очистить список") {
                store.clearAll()
            }
            .buttonStyle(win95ButtonStyle)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.black.opacity(0.4)).frame(height: 1)
        }
    }

    private var plainLinkStyle: Win95LinkButtonStyle { Win95LinkButtonStyle() }
    private var win95ButtonStyle: Win95BevelButtonStyle { Win95BevelButtonStyle() }
}

private struct Win95BevelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11))
            .foregroundColor(.black)
            .padding(.horizontal, 12)
            .frame(height: 22)
            .background(Color(nsColor: NSColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1)))
            .overlay(
                Rectangle()
                    .stroke(
                        LinearGradient(
                            colors: configuration.isPressed
                                ? [Color(white: 0.9), Color(white: 0.4)]
                                : [Color(white: 0.4), Color(white: 0.95)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

private struct Win95LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11))
            .foregroundColor(.blue)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}