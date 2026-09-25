import SwiftUI

extension Color {
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}

struct SkinTheme {
    let toolbarTop: Color
    let toolbarBottom: Color
    let bevelFace: [Color]
    let bevelPressed: [Color]
    let bevelEdge: Color
    let buttonForeground: Color
    let buttonFont: Font
    let accent: Color
    let progressTint: Color
    let statusForeground: Color
    let contentBackground: Color
    let labelForeground: Color

    let bevelLight: Color
    let bevelDark: Color
    var disabledForeground: Color { bevelDark }

    let chromeFlat: Bool
    let titleBarBackground: Color
    let titleBarForeground: Color
    let titleBarHeight: CGFloat
    let showsMenuBar: Bool
    let menuBarHeight: CGFloat
    let toolbarHeight: CGFloat
    let locationRowHeight: CGFloat
    let showsDirectoryRow: Bool
    let directoryRowHeight: CGFloat
    let directoryLabels: [String]
    let locationLabel: String
    let navButtonVertical: Bool
}

extension AppSkin {
    var theme: SkinTheme {
        switch self {
        case .cheesecake:
            return SkinTheme(
                toolbarTop: Color(rgb: 0xC0C0C0),
                toolbarBottom: Color(rgb: 0xC0C0C0),
                bevelFace: [Color(rgb: 0xC0C0C0)],
                bevelPressed: [Color(rgb: 0xB8B8B8)],
                bevelEdge: Color(rgb: 0x000000),
                buttonForeground: Color(rgb: 0x000000),
                buttonFont: .system(size: 11, weight: .bold),
                accent: Color(rgb: 0x000080),
                progressTint: Color(rgb: 0x000080),
                statusForeground: Color(rgb: 0x000000),
                contentBackground: Color(rgb: 0xC0C0C0),
                labelForeground: Color(rgb: 0x000000),
                bevelLight: Color(rgb: 0xFFFFFF),
                bevelDark: Color(rgb: 0x808080),
                chromeFlat: true,
                titleBarBackground: Color(rgb: 0x000080),
                titleBarForeground: Color(rgb: 0xFFFFFF),
                titleBarHeight: 22,
                showsMenuBar: true,
                menuBarHeight: 24,
                toolbarHeight: 58,
                locationRowHeight: 30,
                showsDirectoryRow: true,
                directoryRowHeight: 28,
                directoryLabels: ["Welcome", "What's New!", "What's Cool!", "Destinations", "Net Search", "People", "Software"],
                locationLabel: "Location:",
                navButtonVertical: true
            )
        case .internetExplorer:
            return SkinTheme(
                toolbarTop: Color(red: 0.20, green: 0.44, blue: 0.73),
                toolbarBottom: Color(red: 0.08, green: 0.28, blue: 0.54),
                bevelFace: [
                    Color(red: 0.31, green: 0.53, blue: 0.79),
                    Color(red: 0.22, green: 0.45, blue: 0.72),
                    Color(red: 0.14, green: 0.35, blue: 0.62)
                ],
                bevelPressed: [
                    Color(red: 0.12, green: 0.31, blue: 0.57),
                    Color(red: 0.21, green: 0.44, blue: 0.70),
                    Color(red: 0.31, green: 0.53, blue: 0.79)
                ],
                bevelEdge: Color(white: 0.02, opacity: 0.55),
                buttonForeground: .white,
                buttonFont: .system(size: 13, weight: .bold),
                accent: Color(red: 1.00, green: 0.85, blue: 0.10),
                progressTint: Color(red: 1.00, green: 0.85, blue: 0.10),
                statusForeground: .white,
                contentBackground: Color(red: 0.68, green: 0.72, blue: 0.80),
                labelForeground: Color(white: 0.98),
                bevelLight: Color(white: 0.95),
                bevelDark: Color(white: 0.15),
                chromeFlat: false,
                titleBarBackground: Color(red: 0.08, green: 0.28, blue: 0.54),
                titleBarForeground: .white,
                titleBarHeight: 22,
                showsMenuBar: false,
                menuBarHeight: 0,
                toolbarHeight: 44,
                locationRowHeight: 34,
                showsDirectoryRow: false,
                directoryRowHeight: 0,
                directoryLabels: [],
                locationLabel: "Адрес:",
                navButtonVertical: false
            )
        }
    }
}

struct BevelFace: View {
    let theme: SkinTheme
    var isPressed = false
    var height: CGFloat = 28

    var body: some View {
        let light = isPressed ? theme.bevelDark : theme.bevelLight
        let dark = isPressed ? theme.bevelLight : theme.bevelDark

        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: isPressed ? theme.bevelPressed : theme.bevelFace,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Rectangle()
                .fill(light)
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 1)
                .padding(.top, 1)

            Rectangle()
                .fill(light)
                .frame(width: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
                .padding(.leading, 1)

            Rectangle()
                .fill(dark)
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 1)
                .padding(.bottom, 1)

            Rectangle()
                .fill(dark)
                .frame(width: 1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.vertical, 1)
                .padding(.trailing, 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(theme.bevelEdge, lineWidth: 1)
        )
        .frame(height: height)
    }
}

struct BevelButtonStyle: ButtonStyle {
    let theme: SkinTheme
    var vertical = false

    func makeBody(configuration: Configuration) -> some View {
        let height: CGFloat = vertical ? max(theme.toolbarHeight - 16, 32) : 26
        configuration.label
            .padding(.horizontal, vertical ? 4 : 9)
            .frame(height: height)
            .background(BevelFace(theme: theme, isPressed: configuration.isPressed, height: height))
            .contentShape(Rectangle())
    }
}