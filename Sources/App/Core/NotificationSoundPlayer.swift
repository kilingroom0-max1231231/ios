import AudioToolbox
import Foundation

enum NotificationSoundPlayer {
    /// Standard iOS tri-tone style alert (SMS received).
    private static let defaultSoundID: SystemSoundID = 1007

    static func playMessageReceived() {
        AudioServicesPlaySystemSound(defaultSoundID)
    }
}
