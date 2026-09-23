import Foundation

/// Minimal flag surface used by gameplay systems. `GameProgress` stays the
/// single source of truth for persisted flags; this adapter bridges it to the
/// typed bus and a `set(_:to:)` form the tracker expects.
@MainActor
protocol FlagStore: AnyObject {
    func contains(_ key: String) -> Bool
    func set(_ key: String, to value: Bool)
}

/// Backs a `FlagStore` with the app's `GameProgress` and announces every
/// change as `.flagChanged` on the `GameBus`.
@MainActor
final class GameProgressFlagStore: FlagStore {
    private let game: GameProgress
    private let bus: GameBus

    init(game: GameProgress, bus: GameBus) {
        self.game = game
        self.bus = bus
    }

    func contains(_ key: String) -> Bool {
        game.flags.contains(key)
    }

    func set(_ key: String, to value: Bool) {
        if value {
            game.setFlag(key)
            bus.publish(.flagChanged(FlagChangedEvent(key: key, value: true)))
        } else if game.flags.contains(key) {
            // GameProgress only records set flags; announce the best-effort
            // clearing anyway so listeners at least see the intent.
            bus.publish(.flagChanged(FlagChangedEvent(key: key, value: false)))
        }
    }
}