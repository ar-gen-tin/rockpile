import Foundation
import Observation

@MainActor
@Observable
final class EmotionState {
    private(set) var currentEmotion: ClawEmotion = .neutral

    private var happyScore: Double = 0
    private var sadScore: Double = 0

    private static let sadThreshold: Double = 0.45
    private static let happyThreshold: Double = 0.6
    private static let angryEscalation: Double = 0.9
    private static let decayRate: Double = 0.92
    private static let crossDecay: Double = 0.90
    private static let neutralDecay: Double = 0.85

    func recordEmotion(_ emotion: ClawEmotion, intensity: Double) {
        switch emotion {
        case .happy:
            happyScore = min(1.0, happyScore + intensity)
            sadScore *= Self.crossDecay
        case .sad:
            sadScore = min(1.0, sadScore + intensity)
            happyScore *= Self.crossDecay
        case .angry:
            sadScore = min(1.0, sadScore + intensity)
            happyScore *= Self.crossDecay
        case .neutral:
            happyScore *= Self.neutralDecay
            sadScore *= Self.neutralDecay
        }

        updateCurrentEmotion()
    }

    func decay() {
        happyScore *= Self.decayRate
        sadScore *= Self.decayRate
        updateCurrentEmotion()
    }

    func reset() {
        happyScore = 0
        sadScore = 0
        currentEmotion = .neutral
    }

    private func updateCurrentEmotion() {
        if sadScore >= Self.angryEscalation {
            currentEmotion = .angry
        } else if sadScore >= Self.sadThreshold {
            currentEmotion = .sad
        } else if happyScore >= Self.happyThreshold {
            currentEmotion = .happy
        } else {
            currentEmotion = .neutral
        }
    }
}
