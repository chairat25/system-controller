@testable import SoundControlCore

extension AppConfig {
    /// The defaults with sound switched on and the recommended triggers enabled; the shipped default is all off.
    static var playing: AppConfig {
        AppConfig.default.withListening(true).withRecommendedEnabled()
    }
}
