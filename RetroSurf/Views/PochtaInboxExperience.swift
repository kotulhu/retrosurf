import SwiftUI

struct PochtaInboxExperience: View {
    let siteID: String
    let onBack: () -> Void
    let onOpenSite: (String) -> Void

    @EnvironmentObject private var mailbox: MailboxManager

    @State private var selected: MailMessage?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd MMM yyyy, HH:mm"
        return formatter
    }()

    var body: some View {
        Group {
            if let selected {
                detailView(selected)
            } else {
                listView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(beige)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme?.lowercased() == "retrosurf", let host = url.host {
                onOpenSite(host)
                return .handled
            }
            return .systemAction
        })
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Почта.SU")
                .font(.custom("Times New Roman", size: 34).weight(.bold))
                .foregroundColor(Color(red: 0.55, green: 0.1, blue: 0.1))
            Text("Ваш почтовый ящик")
                .font(.custom("Times New Roman", size: 13))
                .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.35))
        }
    }

    private var listView: some View {
        VStack(spacing: 14) {
            header

            if mailbox.messages.isEmpty {
                Text("Писем пока нет.")
                    .font(.custom("Times New Roman", size: 14))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(mailbox.messages) { mail in
                            mailRow(mail)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                .background(Color(red: 0.98, green: 0.98, blue: 0.94))
                .padding(.horizontal, 40)
            }

            Button(action: onBack) {
                Text("Вернуться")
                    .font(.custom("Times New Roman", size: 15).weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.45, green: 0.2, blue: 0.1))
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .padding(.top, 24)
    }

    private func mailRow(_ mail: MailMessage) -> some View {
        Button {
            selected = mail
            mailbox.markRead(mail.id)
        } label: {
            HStack(spacing: 10) {
                Text(mail.isRead ? " " : "●")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(Color(red: 0.6, green: 0.1, blue: 0.1))
                    .frame(width: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mail.subject)
                        .font(.custom("Times New Roman", size: 14).weight(mail.isRead ? .regular : .bold))
                        .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                        .lineLimit(1)
                    Text(mail.from)
                        .font(.custom("Times New Roman", size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(Self.dateFormatter.string(from: mail.date))
                    .font(.custom("Times New Roman", size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white)
            .overlay(Rectangle().stroke(Color(red: 0.75, green: 0.72, blue: 0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func detailView(_ mail: MailMessage) -> some View {
        VStack(spacing: 12) {
            header
                .padding(.top, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(mail.subject)
                        .font(.custom("Times New Roman", size: 18).weight(.bold))
                        .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                    HStack {
                        Text("От: \(mail.from)")
                            .font(.custom("Times New Roman", size: 13).weight(.bold))
                        Spacer()
                        Text(Self.dateFormatter.string(from: mail.date))
                            .font(.custom("Times New Roman", size: 12))
                            .foregroundColor(.secondary)
                    }
                    Divider()
                    richBody(mail.body)
                        .font(.custom("Times New Roman", size: 14))
                        .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.98, green: 0.98, blue: 0.94))
                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 6)

            Button("Назад к письмам") {
                selected = nil
            }
            .font(.custom("Times New Roman", size: 14).weight(.bold))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 7)
            .background(Color(red: 0.45, green: 0.2, blue: 0.1))
            .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func richBody(_ body: String) -> Text {
        var attributed = AttributedString()
        var remaining = Substring(body)
        while let range = remaining.range(of: #"\{([^{}]+)\}"#, options: .regularExpression) {
            let before = String(remaining[..<range.lowerBound])
            if !before.isEmpty {
                attributed += AttributedString(before)
            }
            let match = String(remaining[range])
            let marker = String(match.dropFirst().dropLast())
            var linkPart = AttributedString(marker)
            linkPart.foregroundColor = Color(red: 0, green: 0, blue: 0.6)
            linkPart.underlineStyle = .single
            if let url = URL(string: "retrosurf://\(marker)") {
                linkPart.link = url
            }
            attributed += linkPart
            remaining = remaining[range.upperBound...]
        }
        if !remaining.isEmpty {
            attributed += AttributedString(String(remaining))
        }
        return Text(attributed)
    }

    private var beige: Color {
        Color(red: 0.95, green: 0.92, blue: 0.84)
    }
}