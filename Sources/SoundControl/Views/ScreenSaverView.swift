import AppKit
import SwiftUI
import SoundControlCore

/// The Smartheart Screen Saver: title on top, the chosen widgets in the middle, the owner's
/// fingerprint zone at the bottom, the working Claude sessions in the corner the owner picked and a mascot strolling below.
/// The screen dims with `dimmer`; the clock and the mascot can each hold their own level while the rest goes dark.
struct ScreenSaverView<Unlock: View, Corner: View>: View {
    let settings: ScreenSaverSettings
    let dimmer: ScreenSaverDimmer
    /// The animal strolling along the bottom; `.none` on screens that should not have one.
    let mascot: Mascot
    var display: NSScreen? = nil
    var onUpdate: ScreenSaverUpdate = { _ in }
    @ViewBuilder let unlock: () -> Unlock
    @ViewBuilder let corner: () -> Corner

    @State private var itemSizes: [ScreenSaverItem: CGSize] = [:]
    @State private var activeDrag: ActiveWidgetDrag?

    private var screen: Double { dimmer.brightness }

    var body: some View {
        ZStack {
            Color.black
            ScreenSaverBackgroundView(background: settings.background,
                                      customName: settings.customBackgroundName,
                                      display: display)
                .opacity(screen)
            if mascot != .none {
                let light = settings.mascotBrightness(screen: screen)
                MascotStroll(mascot: mascot, isPaused: light < Layout.darkEnough)
                    .padding(.horizontal, Layout.sideInset)
                    .padding(.vertical, Layout.mascotVerticalInset)
                    .opacity(light)
            }
            widgetsCanvas
            header
                .opacity(screen)
                .padding(.top, Layout.topInset)
                .padding(.horizontal, Layout.sideInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
            unlock()
                .padding(.bottom, Layout.bottomInset)
                .padding(.horizontal, Layout.sideInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .opacity(screen)
                .zIndex(1000)
        }
        .foregroundStyle(.white)
        .animation(.linear(duration: 0.5), value: screen)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "heart.fill").foregroundStyle(Theme.accent)
                Text("Smartheart Screen Saver").font(.title2.weight(.semibold))
            }
            Text("Only the owner can unlock.").font(.callout).foregroundStyle(.secondary)
        }
    }

    private var widgetsCanvas: some View {
        GeometryReader { proxy in
            let canvas = CanvasSize(width: Double(proxy.size.width), height: Double(proxy.size.height))
            let measured = itemSizes.mapValues { CanvasSize(width: Double($0.width), height: Double($0.height)) }
            let visibleItems = settings.widgetOrder.filter { isVisible($0) }
            let effectiveOrder: [ScreenSaverItem] = {
                guard let dragging = activeDrag?.item, visibleItems.contains(dragging) else {
                    return visibleItems
                }
                return visibleItems.filter { $0 != dragging } + [dragging]
            }()
            let centers = resolveCenters(for: effectiveOrder, measured: measured, canvas: canvas)
            let rects: [ScreenSaverItem: CanvasRect] = effectiveOrder.reduce(into: [:]) { acc, item in
                guard let center = centers[item],
                      let size = measured[item],
                      size.width > 1,
                      size.height > 1 else { return }
                acc[item] = CanvasRect(center: center, size: size)
            }
            let overlaps = WidgetCanvasLayout.overlapStates(order: effectiveOrder, rects: rects)

            ZStack {
                ForEach(Array(visibleItems.enumerated()), id: \.element) { index, item in
                    let isDragging = activeDrag?.item == item
                    let overlap = overlaps[item] ?? (overlapsLower: false, isCoveredByUpper: false)
                    let center = centers[item] ?? CanvasPoint(x: canvas.width / 2, y: canvas.height / 2)
                    let opacity = brightness(for: item) * (overlap.isCoveredByUpper && !isDragging ? 0.82 : 1.0)

                    widgetContent(for: item, isDragging: isDragging, isOverlappingLower: overlap.overlapsLower)
                        .contentShape(Rectangle())
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { newSize in
                            if itemSizes[item] != newSize {
                                itemSizes[item] = newSize
                            }
                        }
                        .opacity(opacity)
                        .scaleEffect(isDragging ? 1.02 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isDragging)
                        .pointerStyle(isDragging ? .grabActive : .grabIdle)
                        .position(x: center.x, y: center.y)
                        .zIndex(isDragging ? 500 : Double(index))
                        .simultaneousGesture(dragGesture(for: item, currentCenter: center, measured: measured, canvas: canvas))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .coordinateSpace(name: Layout.canvasSpace)
        }
    }

    private func isVisible(_ item: ScreenSaverItem) -> Bool {
        switch item {
        case .clock: settings.shows(.clock)
        case .calendar: settings.shows(.calendar)
        case .claudeUsage: settings.shows(.claudeUsage)
        case .sessions: settings.showsSessions
        }
    }

    private func brightness(for item: ScreenSaverItem) -> Double {
        item == .clock ? settings.clockBrightness(screen: screen) : screen
    }

    @ViewBuilder
    private func widgetContent(for item: ScreenSaverItem, isDragging: Bool, isOverlappingLower: Bool) -> some View {
        switch item {
        case .clock:
            ClockWidget(isDragging: isDragging, isOverlappingLower: isOverlappingLower)
        case .calendar:
            CalendarWidget(isDragging: isDragging, isOverlappingLower: isOverlappingLower)
        case .claudeUsage:
            ClaudeUsageWidget(isDragging: isDragging, isOverlappingLower: isOverlappingLower)
        case .sessions:
            corner()
                .padding(8)
                .widgetGlassBackdrop(
                    showCard: isDragging || isOverlappingLower,
                    isDragging: isDragging,
                    isOverlappingLower: isOverlappingLower,
                    cornerRadius: 16
                )
        }
    }

    private func resolveCenters(
        for items: [ScreenSaverItem],
        measured: [ScreenSaverItem: CanvasSize],
        canvas: CanvasSize
    ) -> [ScreenSaverItem: CanvasPoint] {
        var result: [ScreenSaverItem: CanvasPoint] = [:]
        for item in items {
            let size = measured[item] ?? fallbackSize(for: item)
            if let drag = activeDrag, drag.item == item {
                let proposed = CanvasPoint(
                    x: Double(drag.startCenter.x + drag.translation.width),
                    y: Double(drag.startCenter.y + drag.translation.height)
                )
                result[item] = WidgetCanvasLayout.clampedCenter(proposed, itemSize: size, canvasSize: canvas)
            } else {
                result[item] = WidgetCanvasLayout.center(
                    for: item,
                    settings: settings,
                    itemSize: size,
                    measuredSizes: measured,
                    canvasSize: canvas
                )
            }
        }
        return result
    }

    private func dragGesture(
        for item: ScreenSaverItem,
        currentCenter: CanvasPoint,
        measured: [ScreenSaverItem: CanvasSize],
        canvas: CanvasSize
    ) -> some Gesture {
        DragGesture(minimumDistance: item == .sessions ? 6 : 3, coordinateSpace: .named(Layout.canvasSpace))
            .onChanged { value in
                let startCenter = activeDrag?.item == item
                    ? activeDrag!.startCenter
                    : CGPoint(x: currentCenter.x, y: currentCenter.y)
                activeDrag = ActiveWidgetDrag(item: item, startCenter: startCenter, translation: value.translation)
            }
            .onEnded { value in
                let startCenter = activeDrag?.item == item
                    ? activeDrag!.startCenter
                    : CGPoint(x: currentCenter.x, y: currentCenter.y)
                let size = measured[item] ?? fallbackSize(for: item)
                let proposed = CanvasPoint(
                    x: Double(startCenter.x + value.translation.width),
                    y: Double(startCenter.y + value.translation.height)
                )
                let clamped = WidgetCanvasLayout.clampedCenter(proposed, itemSize: size, canvasSize: canvas)
                let normalized = WidgetCanvasLayout.normalizedPosition(fromCenter: clamped, itemSize: size, canvasSize: canvas)
                activeDrag = nil
                onUpdate { $0.moving(item, to: normalized) }
            }
    }

    private func fallbackSize(for item: ScreenSaverItem) -> CanvasSize {
        switch item {
        case .clock: CanvasSize(width: 320, height: 170)
        case .calendar: CanvasSize(width: 280, height: 270)
        case .claudeUsage: CanvasSize(width: 270, height: 200)
        case .sessions: CanvasSize(width: 260, height: 110)
        }
    }
}

private struct ActiveWidgetDrag {
    let item: ScreenSaverItem
    let startCenter: CGPoint
    let translation: CGSize
}

private enum Layout {
    static let canvasSpace = "screenSaverWidgetCanvas"
    static let topInset: CGFloat = 56
    static let bottomInset: CGFloat = 64
    static let sideInset: CGFloat = 48
    static let mascotVerticalInset: CGFloat = 16
    /// Below this brightness the mascot cannot be seen, so it stops drawing.
    static let darkEnough = 0.02
}

/// Renders the chosen screen saver backdrop (solid pitch black, gradient, starfield, macOS wallpaper or custom photo).
struct ScreenSaverBackgroundView: View {
    let background: ScreenSaverBackground
    let customName: String?
    var display: NSScreen? = nil

    @State private var loadedImage: NSImage?

    var body: some View {
        content
            .ignoresSafeArea()
            .task(id: "\(background.rawValue)-\(customName ?? "")") {
                loadedImage = await loadImage()
            }
            .onDisappear {
                loadedImage = nil
            }
    }

    @ViewBuilder
    private var content: some View {
        switch background {
        case .pitchBlack:
            Color.black
        case .midnight:
            midnightGradient
        case .aurora:
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.14, blue: 0.16),
                    Color(red: 0.07, green: 0.23, blue: 0.20),
                    Color(red: 0.13, green: 0.06, blue: 0.23),
                    Color(red: 0.01, green: 0.03, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .ember:
            LinearGradient(
                colors: [
                    Color(red: 0.20, green: 0.07, blue: 0.04),
                    Color(red: 0.12, green: 0.03, blue: 0.06),
                    Color(red: 0.02, green: 0.01, blue: 0.02)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        case .ocean:
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.11, blue: 0.22),
                    Color(red: 0.03, green: 0.19, blue: 0.27),
                    Color(red: 0.01, green: 0.03, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .forest:
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.13, blue: 0.08),
                    Color(red: 0.06, green: 0.18, blue: 0.11),
                    Color(red: 0.01, green: 0.04, blue: 0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .cosmos:
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.02, blue: 0.09),
                        Color(red: 0.05, green: 0.04, blue: 0.14),
                        Color(red: 0.01, green: 0.01, blue: 0.04)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                CosmosStarfield()
            }
        case .desktopWallpaper, .customImage:
            if let loadedImage {
                GeometryReader { proxy in
                    Image(nsImage: loadedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
                .overlay(Color.black.opacity(0.35))
            } else {
                midnightGradient
            }
        }
    }

    private var midnightGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.06, blue: 0.18),
                Color(red: 0.08, green: 0.05, blue: 0.22),
                Color(red: 0.01, green: 0.02, blue: 0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func loadImage() async -> NSImage? {
        switch background {
        case .customImage:
            return await Task.detached(priority: .utility) {
                ScreenSaverBackgroundStore.loadCustomImage()
            }.value
        case .desktopWallpaper:
            let targetScreen = display ?? NSScreen.main ?? NSScreen.screens.first
            let url = targetScreen.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
            return await Task.detached(priority: .utility) {
                ScreenSaverBackgroundStore.loadDesktopWallpaper(at: url)
            }.value
        default:
            return nil
        }
    }
}

/// Deterministic starfield drawn once without allocating star arrays.
private struct CosmosStarfield: View {
    private static let starCount = 120

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            for index in 0..<Self.starCount {
                let x = unit(index, salt: 1) * size.width
                let y = unit(index, salt: 2) * size.height
                let radius = 0.6 + unit(index, salt: 3) * 1.4
                let opacity = 0.20 + unit(index, salt: 4) * 0.55
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
            }
        }
        .allowsHitTesting(false)
    }

    private func unit(_ index: Int, salt: UInt64) -> Double {
        var value = 0x517C_C1B7_2722_0A95 &+ UInt64(index) &* 0x9E37_79B9_7F4A_7C15 &+ salt &* 0xD1B5_4A32_D192_ED03
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value >> 11) / Double(1 << 53)
    }
}
