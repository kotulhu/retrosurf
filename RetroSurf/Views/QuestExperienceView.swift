import SwiftUI

struct QuestExperienceInfo: Equatable {
    let experienceID: String
    let siteID: String
}

struct QuestExperienceView: View {
    let info: QuestExperienceInfo
    let onBack: () -> Void

    @EnvironmentObject private var quests: QuestManager
    @EnvironmentObject private var game: GameProgress

    @State private var stage: Stage = .form
    @State private var login = ""
    @State private var password = ""
    @State private var petName = ""
    @State private var subscribe = true

    private enum Stage {
        case form
        case success(login: String)
    }

    var body: some View {
        Group {
            switch stage {
            case .form:
                formView
            case .success(let login):
                successView(login: login)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(beige)
    }

    private var formView: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Люди.su")
                    .font(.custom("Times New Roman", size: 40).weight(.bold))
                    .foregroundColor(Color(red: 0.55, green: 0.1, blue: 0.1))
                Text("Регистрация бесплатного электронного ящика")
                    .font(.custom("Times New Roman", size: 14))
                    .foregroundColor(.secondary)

                VStack(spacing: 10) {
                    fieldRow(label: "Логин:") {
                        TextField("", text: $login)
                            .textFieldStyle(.plain)
                            .font(.custom("Times New Roman", size: 13))
                    }
                    fieldRow(label: "Пароль:") {
                        SecureField("", text: $password)
                            .textFieldStyle(.plain)
                            .font(.custom("Times New Roman", size: 13))
                    }
                    fieldRow(label: "Секретный вопрос:\nкличка вашего питомца") {
                        TextField("", text: $petName)
                            .textFieldStyle(.plain)
                            .font(.custom("Times New Roman", size: 13))
                    }
                }
                .padding(.vertical, 8)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                .background(Color.white)

                Toggle("Получать новости и специальные предложения", isOn: $subscribe)
                    .toggleStyle(.checkbox)
                    .font(.custom("Times New Roman", size: 12))
                    .padding(.trailing, 8)

                Button(action: register) {
                    Text("Зарегистрироваться")
                        .font(.custom("Times New Roman", size: 15).weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.45, green: 0.2, blue: 0.1))
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.5)

                Text("Бесплатно навсегда! Хранилище 2 Мб. Один ящик на пользователя.")
                    .font(.custom("Times New Roman", size: 12))
                    .foregroundColor(Color(red: 0.0, green: 0.4, blue: 0.0))
            }
            .frame(width: 460)
            .padding(.vertical, 30)
        }
    }

    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.custom("Times New Roman", size: 13))
                .frame(width: 150, alignment: .trailing)
                .padding(.vertical, 4)
            content()
                .frame(width: 220)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(red: 0.98, green: 0.98, blue: 0.93))
                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
        }
    }

    private func successView(login: String) -> some View {
        VStack(spacing: 20) {
            Text("Добро пожаловать!")
                .font(.custom("Times New Roman", size: 44).weight(.bold))
                .foregroundColor(Color(red: 0.0, green: 0.45, blue: 0.0))
            Text("Ваш адрес:")
                .font(.custom("Times New Roman", size: 18))
            Text("\(login)@pochta.su")
                .font(.custom("Courier New", size: 26).weight(.bold))
                .foregroundColor(Color(red: 0.55, green: 0.1, blue: 0.1))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            Text("Теперь вы можете отправлять и получать письма со всего Света!")
                .font(.custom("Times New Roman", size: 14))
                .foregroundColor(.secondary)

            decorBanner

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
        }
        .padding(.horizontal, 40)
    }

    private var decorBanner: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { _ in
                Text("ВЫИГРАЙТЕ МИЛЛИОН! НАЖМИТЕ ЗДЕСЬ!")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.yellow)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
            }
        }
    }

    private var canSubmit: Bool {
        !login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    private func register() {
        let trimmedLogin = login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLogin.isEmpty, !password.isEmpty else { return }
        if let questID = quests.questID(forSiteID: info.siteID) {
            quests.markCompleted(questID)
        }
        game.recordVisit(info.siteID)
        stage = .success(login: trimmedLogin)
    }

    private var beige: Color {
        Color(red: 0.95, green: 0.92, blue: 0.84)
    }
}
