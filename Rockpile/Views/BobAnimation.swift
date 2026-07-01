import Foundation

/// Piecewise cubic easeInOut bob: lingers at peaks like SwiftUI's .easeInOut
/// Returns a value in [-amplitude, +amplitude] that oscillates smoothly over `duration` seconds.
func bobOffset(at date: Date, duration: Double, amplitude: CGFloat) -> CGFloat {
    guard amplitude > 0 else { return 0 }
    let t = date.timeIntervalSinceReferenceDate
    let phase = (t / duration).truncatingRemainder(dividingBy: 1.0)
    let inFirstHalf = phase < 0.5
    let u = inFirstHalf ? phase * 2 : (phase - 0.5) * 2
    let eased = u < 0.5 ? 4 * u * u * u : 1 - pow(-2 * u + 2, 3) / 2
    let wave = inFirstHalf ? 1 - 2 * eased : -1 + 2 * eased
    return wave * amplitude
}

private let trembleFrequencyHz: Double = 2

/// Rapid horizontal shake for distressed states (e.g., angry).
func trembleOffset(at date: Date, amplitude: CGFloat) -> CGFloat {
    guard amplitude > 0 else { return 0 }
    let t = date.timeIntervalSinceReferenceDate
    return CGFloat(sin(t * trembleFrequencyHz * .pi * 2)) * amplitude
}
