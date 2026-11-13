import Observation
import SwiftUI
import SoundControlCore

/// Which drawer is open on one screen. Reports opening and closing so the dimmer can preview.
@MainActor
@Observable
final class DrawerState {
    var drawer: ScreenSaverDrawer = .closed {
        didSet {
            let wasOpen = oldValue != .closed
            let isOpen = drawer != .closed
            if wasOpen != isOpen { onOpenChange(isOpen) }
        }
    }

    @ObservationIgnored private let onOpenChange: @MainActor (Bool) -> Void

    init(onOpenChange: @escaping @MainActor (Bool) -> Void) {
        self.onOpenChange = onOpenChange
    }
}

/// The settings drawers on the screen saver: dimming slides in from the left, what shows from the right.
/// Changes save right away and the screen behind shows the result.
struct ScreenSaverDrawers: View {
    let state: DrawerState
    let link: ScreenSaverLink
    let dimmer: ScreenSaverDimmer

    var body: some View {
        let settings = link.settings
        ZStack {
            if state.drawer != .closed {
                // A click anywhere outside the drawer closes it.
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { state.drawer = .closed }
            }
            if state.drawer == .dimming {
                panel("Dimming", systemImage: "moon", edge: .leading) {
                    DimmingControls(settings: settings, update: link.update)
                }
            }
            if state.drawer == .widgets {
                panel("On screen", systemImage: "square.grid.2x2", edge: .trailing) {
                    WidgetToggles(settings: settings, update: link.update)
                    SessionsCornerRow(settings: settings, update: link.update)
                    WidgetLayoutResetButton(settings: settings, update: link.update)
                    Divider()
                    SectionHeader("Background")
                    BackgroundControls(settings: settings, update: link.update)
                    Divider()
                    SectionHeader("Mascot")
                    Toggle("Hide mascot", isOn: Binding(
                        get: { settings.activeMascot == .none },
                        set: { isHidden in link.update { $0.withMascotHidden(isHidden) } }
                    ))
                    MascotGrid(selection: settings.activeMascot) { mascot in link.update { $0.withMascot(mascot) } }
                        .opacity(settings.activeMascot == .none ? 0.55 : 1)
                    Divider()
                    SectionHeader("Stays bright")
                    StayLitControls(settings: settings, update: link.update)
                }
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.12), value: state.drawer)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private func panel<Content: View>(_ title: String, systemImage: String, edge: HorizontalEdge,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(title, systemImage: systemImage).font(.headline)
                Spacer()
                Button { state.drawer = .closed } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) { content() }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            Toggle("Show the dimmed look while open", isOn: Binding(get: { dimmer.isPreviewWanted },
                                                                   set: { dimmer.isPreviewWanted = $0 }))
            Text("Swipe back or click outside to close. Changes are saved right away.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: Layout.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Layout.fill, in: RoundedRectangle(cornerRadius: Layout.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Layout.radius, style: .continuous).stroke(.white.opacity(0.1)))
        .padding(Layout.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .leading ? .leading : .trailing)
        .transition(.move(edge: edge == .leading ? .leading : .trailing).combined(with: .opacity))
    }

    private enum Layout {
        static let width: CGFloat = 340
        static let radius: CGFloat = 18
        static let margin: CGFloat = 24
        static let fill = Color(white: 0.11)
    }
}
