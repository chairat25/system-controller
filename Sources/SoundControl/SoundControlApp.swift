import AppKit
import SwiftUI

@main
struct SoundControlApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        // The menu-bar icon and its popup are AppKit (`MenuBarPopup`), so the popup shortcut can open it; the full
        // window is an AppKit window too (`MainWindowController`). SwiftUI still needs one scene, which shows nothing.
        MenuBarExtra("System Controller", systemImage: "slider.horizontal.3", isInserted: .constant(false)) {
            EmptyView()
        }
    }
}
