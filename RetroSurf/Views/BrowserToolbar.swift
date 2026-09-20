import AppKit
import SwiftUI

struct BrowserToolbar: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var engine: BrowserSimulator

    @Binding var address: String
    let onGo: () -> Void
    let onHome: () -> Void
    let onReload: () -> Void
    let onBack: () -> Void
    let onForward: () -> Void
    let canGoBack: Bool
    let canGoForward: Bool
    let onCurate: () -> Void
    let onLibrary: () -> Void

    var body: some View {
        let theme = settings.skin.theme

        VStack(spacing: 0) {
            if theme.showsMenuBar {
                ChromeTitleBar(theme: theme)
                ChromeMenuBar(theme: theme, engine: engine, onHome: onHome, onReload: onReload, onBack: onBack, onForward: onForward)
            } else {
                ChromeTitleBar(theme: theme)
                    .background(theme.titleBarBackground)
            }

            toolbarRow(theme: theme)

            AddressBar(address: $address, onGo: onGo, theme: theme)
                .padding(.horizontal, 10)
                .frame(height: theme.locationRowHeight)

            if theme.showsDirectoryRow {
                DirectoryRow(theme: theme, onHome: onHome)
            }
        }
        .background(chromeBackground(theme: theme))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.bevelEdge)
                .frame(height: 2)
        }
    }

    private func chromeBackground(theme: SkinTheme) -> AnyShapeStyle {
        if theme.chromeFlat {
            return AnyShapeStyle(theme.toolbarTop)
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [theme.toolbarTop, theme.toolbarBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func toolbarRow(theme: SkinTheme) -> some View {
        HStack(spacing: theme.navButtonVertical ? 2 : 5) {
            NavButton(title: "Back", systemImage: "arrow.left", theme: theme, vertical: theme.navButtonVertical, isActive: canGoBack) {
                onBack()
            }
            NavButton(title: "Forward", systemImage: "arrow.right", theme: theme, vertical: theme.navButtonVertical, isActive: canGoForward) {
                onForward()
            }
            NavButton(title: "Home", systemImage: "house", theme: theme, vertical: theme.navButtonVertical) {
                onHome()
            }
            NavButton(title: "Reload", systemImage: "arrow.counterclockwise", theme: theme, vertical: theme.navButtonVertical) {
                onReload()
            }
            NavButton(title: theme.navButtonVertical ? "Images" : "Search", systemImage: "photo", theme: theme, vertical: theme.navButtonVertical, isActive: false) {
                engine.notifyUnavailable("Картинки")
            }
            NavButton(title: "Print", systemImage: "printer", theme: theme, vertical: theme.navButtonVertical, isActive: false) {
                engine.notifyUnavailable("Печать")
            }
            NavButton(title: "Find", systemImage: "magnifyingglass", theme: theme, vertical: theme.navButtonVertical, isActive: false) {
                engine.notifyUnavailable("Поиск")
            }
            NavButton(title: "Stop", systemImage: "xmark", theme: theme, vertical: theme.navButtonVertical) {
                engine.stop()
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button(action: onCurate) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.square")
                            .font(.system(size: 12, weight: .bold))
                        Text("Добавить сайт…")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(theme.buttonForeground)
                }
                .buttonStyle(BevelButtonStyle(theme: theme))

                Button(action: onLibrary) {
                    HStack(spacing: 5) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 12, weight: .bold))
                        Text("Мои сайты…")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(theme.buttonForeground)
                }
                .buttonStyle(BevelButtonStyle(theme: theme))

                Text("Скин:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.labelForeground)

                Picker("Скин", selection: $settings.skin) {
                    ForEach(AppSkin.allCases) { skin in
                        Text(skin.title).tag(skin)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }

            BrandLogo(skin: settings.skin, isLoading: engine.isLoading)
                .frame(width: 46, height: theme.navButtonVertical ? 40 : 42)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(height: theme.toolbarHeight)
    }
}

struct ChromeTitleBar: View {
    let theme: SkinTheme

    var body: some View {
        HStack {
            Spacer(minLength: 84)
            Text(title(for: theme))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(theme.titleBarForeground)
                .lineLimit(1)
            Spacer(minLength: 84)
        }
        .frame(height: theme.titleBarHeight)
        .background(theme.titleBarBackground)
    }

    private func title(for theme: SkinTheme) -> String {
        theme.chromeFlat ? "Netscape Navigator — RetroSurf" : "Internet Explorer — RetroSurf"
    }
}

struct ChromeMenuBar: View {
    let theme: SkinTheme
    @ObservedObject var engine: BrowserSimulator
    let onHome: () -> Void
    let onReload: () -> Void
    let onBack: () -> Void
    let onForward: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            menu("File", items: [
                ("Новое окно", { engine.notifyUnavailable("Новое окно") }),
                ("Открыть адрес…", { engine.notifyUnavailable("Открыть адрес") }),
                ("Сохранить как…", { engine.notifyUnavailable("Сохранить как") }),
                ("Выход", { NSApp.terminate(nil) })
            ])
            menu("Edit", items: [
                ("Вырезать", { engine.notifyUnavailable("Вырезать") }),
                ("Копировать", { engine.notifyUnavailable("Копировать") }),
                ("Вставить", { engine.notifyUnavailable("Вставить") }),
                ("Найти…", { engine.notifyUnavailable("Найти") })
            ])
            menu("View", items: [
                ("Перезагрузить", { onReload() }),
                ("Остановить загрузку", { engine.stop() }),
                ("Домашняя страница", { onHome() })
            ])
            menu("Go", items: [
                ("Назад", { onBack() }),
                ("Вперёд", { onForward() }),
                ("Домой", { onHome() })
            ])
            menu("Bookmarks", items: [
                ("Добавить закладку…", { engine.notifyUnavailable("Закладки") }),
                ("Список закладок", { engine.notifyUnavailable("Закладки") })
            ])
            menu("Options", items: [
                ("Скин: Netscape Navigator", { setSkin(.netscape) }),
                ("Скин: Internet Explorer", { setSkin(.internetExplorer) })
            ])
            menu("Directory", items: [
                ("Ориентир.ру", { onHome() }),
                ("Что нового?", { onHome() })
            ])
            menu("Window", items: [
                ("Свернуть окно", { NSApp.keyWindow?.miniaturize(nil) })
            ])
            menu("Help", items: [
                ("О программе…", { engine.notifyUnavailable("О программе") }),
                ("Документация", { engine.notifyUnavailable("Документация") })
            ])
            Spacer()
        }
        .padding(.leading, 8)
        .font(.system(size: 12))
        .foregroundColor(theme.labelForeground)
        .background(theme.toolbarTop)
        .frame(height: theme.menuBarHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.bevelDark).frame(height: 1)
        }
    }

    @EnvironmentObject private var settings: AppSettings

    private func setSkin(_ skin: AppSkin) {
        settings.skin = skin
    }

    private func menu(_ title: String, items: [(String, () -> Void)]) -> some View {
        Menu {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button(item.0, action: item.1)
            }
        } label: {
            Text(title)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

struct DirectoryRow: View {
    let theme: SkinTheme
    let onHome: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(theme.directoryLabels, id: \.self) { label in
                DirectoryButton(label: label, theme: theme) {
                    if label == "Welcome" || label == "What's New!" {
                        onHome()
                    } else {
                        // Каталог ещё не содержит этих разделов.
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .frame(height: theme.directoryRowHeight)
        .background(theme.toolbarTop)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.bevelDark).frame(height: 1)
        }
    }
}

private struct DirectoryButton: View {
    let label: String
    let theme: SkinTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(theme.buttonForeground)
                .padding(.horizontal, 8)
                .frame(height: 21)
        }
        .buttonStyle(BevelButtonStyle(theme: theme))
    }
}

struct NavButton: View {
    let title: String
    let systemImage: String
    let theme: SkinTheme
    var vertical = false
    var isActive = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if vertical {
                    VStack(spacing: 3) {
                        Image(systemName: systemImage)
                            .font(.system(size: 16, weight: .bold))
                        Text(title)
                            .font(.system(size: 10, weight: .bold))
                    }
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: systemImage)
                            .font(.system(size: 11, weight: .bold))
                        Text(title)
                    }
                    .font(theme.buttonFont)
                }
            }
            .foregroundColor(isActive ? theme.buttonForeground : theme.disabledForeground)
        }
        .buttonStyle(BevelButtonStyle(theme: theme, vertical: vertical))
    }
}