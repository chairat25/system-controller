import Foundation
import Observation
import SoundControlCore

/// The app's current language. Views that call `L` read `language`, so they redraw when it changes.
@Observable
@MainActor
final class Localizer {
    static let shared = Localizer()
    var language: AppLanguage = .default
}

/// An English UI string in the app's current language. `%@` in the key is filled with `arguments`.
@MainActor
func L(_ english: String, _ arguments: CustomStringConvertible...) -> String {
    Localizer.shared.language.translate(english, arguments.map(\.description))
}
