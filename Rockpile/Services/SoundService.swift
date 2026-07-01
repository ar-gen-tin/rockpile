import AppKit

enum SoundService {
    static func playNotification() {
        guard !AppSettings.isMuted else { return }
        NSSound.beep()
    }
}
