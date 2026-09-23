import SwiftUI
import AppKit

/// «Загрузки» — the download history panel. 90s palette: grey face, silver
/// headers, Verdana 11, thin 1px separators.
struct DownloadsPanelView: View {
    @ObservedObject var store: DownloadsStore
    let onRedownload: (SiteDownload) -> Void
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
            LazyVStack(spacing: 0) {
                if store.items.isEmpty {
                    VStack {
                        Spacer()
                        Text("Скачанных файлов пока нет.")
                            .font(.system(size: 11))
                            .foregroundColor(Color.black.opacity(0.6))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach(store.items) { item in
                        row(for: item)
                        Divider().overlay(Color.black.opacity(0.15))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(for item: DownloadedFile) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                if item.virusDetected {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
                Text(item.fileName)
                    .font(.system(size: 11))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: 190, alignment: .leading)

            Text(FileSizeFormatter.format(item.sizeBytes))
                .font(.system(size: 11))
                .foregroundColor(.black)
                .frame(width: 70, alignment: .trailing)

            Text(statusText(for: item))
                .font(.system(size: 11))
                .foregroundColor(statusColor(for: item))
                .frame(width: 120, alignment: .leading)

            Text(Self.dateFormatter.string(from: item.startedAt))
                .font(.system(size: 11))
                .foregroundColor(.black)
                .frame(width: 120, alignment: .leading)

            actions(for: item)
                .frame(width: 110, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func actions(for item: DownloadedFile) -> some View {
        switch item.status {
        case .completed:
            HStack(spacing: 8) {
                Button("Открыть папку") {
                    // No-op for now: simulated downloads write nothing to disk.
                }
                .buttonStyle(plainLinkStyle)
                Button("Скачать снова") {
                    onRedownload(item.source)
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

    private func statusText(for item: DownloadedFile) -> String {
        switch item.status {
        case .inProgress:
            let percent = item.sizeBytes > 0
                ? Int((Double(item.bytesSent) / Double(item.sizeBytes)) * 100)
                : 0
            return "Загрузка \(min(percent, 100))%"
        case .completed:
            return "Завершено"
        case .cancelled:
            return "Отменено"
        case .failed:
            return "Ошибка"
        }
    }

    private func statusColor(for item: DownloadedFile) -> Color {
        switch item.status {
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