import Combine

struct HistoryEntry {
    let siteID: String
    let displayDomain: String
}

final class BrowserHistory: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var currentIndex: Int = -1

    var canGoBack: Bool { currentIndex > 0 }
    var canGoForward: Bool { currentIndex < entries.count - 1 }

    var current: HistoryEntry? {
        entries.indices.contains(currentIndex) ? entries[currentIndex] : nil
    }

    func navigate(to entry: HistoryEntry) {
        if currentIndex < entries.count - 1 {
            entries.removeSubrange((currentIndex + 1)...)
        }
        entries.append(entry)
        currentIndex = entries.count - 1
    }

    func back() -> HistoryEntry? {
        guard canGoBack else { return nil }
        currentIndex -= 1
        return current
    }

    func forward() -> HistoryEntry? {
        guard canGoForward else { return nil }
        currentIndex += 1
        return current
    }
}