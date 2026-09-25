import Foundation

enum AppSkin: String, CaseIterable, Identifiable {
    case cheesecake
    case internetExplorer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cheesecake: return "Cheesecake Navigator"
        case .internetExplorer: return "Internet Explorer"
        }
    }
}

final class AppSettings: ObservableObject {
    @Published var skin: AppSkin = .cheesecake
    @Published var maxModemSpeed = 56_000
}