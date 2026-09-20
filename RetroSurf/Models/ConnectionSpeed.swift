import Foundation

/// Byte-level throughput profile of a real-world dial-up line. All values are
/// bytes per second, not bits per second (56 kbit/s ≈ 5600 bytes/s).
struct SpeedProfile: Sendable {
    let minBytesPerSec: Double
    let avgBytesPerSec: Double
    let maxBytesPerSec: Double

    static let dialUp = SpeedProfile(
        minBytesPerSec: 1400,
        avgBytesPerSec: 3300,
        maxBytesPerSec: 5600
    )
}