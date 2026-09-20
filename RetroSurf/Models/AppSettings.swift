import Foundation

enum AppSkin: String, CaseIterable, Identifiable {
    case netscape
    case internetExplorer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .netscape: return "Netscape Navigator"
        case .internetExplorer: return "Internet Explorer"
        }
    }
}

final class AppSettings: ObservableObject {
    @Published var skin: AppSkin = .netscape
    @Published var maxModemSpeed = 56_000
}