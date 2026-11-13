import Foundation

/// A rating write's outcome. Failure is not a playback error: monitoring keeps the last confirmed state.
enum MusicRateResult: Equatable, Sendable {
    case applied(MusicPlayback)
    case unchanged
    case refused(String)
    case failed(String)
}
