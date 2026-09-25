import Combine
import Foundation

/// Registers the hidden lastpage.su site the moment the artifact threshold is
/// reached. Idempotent: re-registering is a no-op, and a fresh game that
/// loses the artifacts does NOT unregister the site — but FinalSiteInstaller
/// exists for the app's lifetime, so this runs once per launch.
@MainActor
final class FinalSiteInstaller {
    private let progress: ProgressStore
    private let registry: SiteRegistry
    private let stats: SessionStats
    private var cancellables: Set<AnyCancellable> = []

    init(progress: ProgressStore, registry: SiteRegistry, stats: SessionStats) {
        self.progress = progress
        self.registry = registry
        self.stats = stats
    }

    /// Subscribes to artifact changes and registers the final site when the
    /// unlock threshold is crossed. If the threshold is already met at start,
    /// registers immediately.
    func start() {
        progress.$artifacts
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.refreshLockState()
            }
            .store(in: &cancellables)
        refreshLockState()
    }

    private func refreshLockState() {
        guard progress.isFinalUnlocked, registry.site(withID: "lastpage") == nil else { return }
        let site = LastPageSite(stats: stats, progress: progress)
        registry.register(site)
        print("[FinalSiteInstaller] lastpage.su открыт")
    }
}