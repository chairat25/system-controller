import AppKit
import ImageIO
import SoundControlCore

/// One animal's rendered frames. The PNG is decoded once into a single bitmap (about 4.9 MB) and every frame is
/// a crop of it, so frames cost no extra memory. Sheets are shared and freed when no mascot on screen uses them.
@MainActor
final class MascotSpriteSheet {
    let layout: MascotSpriteLayout
    private let frames: [CGImage]

    private static var cache: [Mascot: WeakSheet] = [:]

    private struct WeakSheet {
        weak var sheet: MascotSpriteSheet?
    }

    private init(layout: MascotSpriteLayout, frames: [CGImage]) {
        self.layout = layout
        self.frames = frames
    }

    /// The sheet for this animal, or nil when it is drawn from shapes instead or its PNG is missing.
    static func shared(for mascot: Mascot) -> MascotSpriteSheet? {
        if let sheet = cache[mascot]?.sheet { return sheet }
        guard let layout = MascotSpriteLayout.forMascot(mascot),
              let url = url(for: mascot),
              let image = decoded(url) else { return nil }
        let side = MascotSpriteLayout.framePixels
        let frames = (0..<layout.frames.count).compactMap { index in
            image.cropping(to: CGRect(x: index % MascotSpriteLayout.columns * side,
                                      y: index / MascotSpriteLayout.columns * side, width: side, height: side))
        }
        guard frames.count == layout.frames.count else { return nil }
        let sheet = MascotSpriteSheet(layout: layout, frames: frames)
        cache[mascot] = WeakSheet(sheet: sheet)
        return sheet
    }

    func frame(_ index: Int) -> CGImage? {
        frames.indices.contains(index) ? frames[index] : nil
    }

    /// Inside the app bundle; while developing with `swift run`, the repo's own folder.
    private static func url(for mascot: Mascot) -> URL? {
        if let bundled = Bundle.main.url(forResource: mascot.rawValue, withExtension: "png", subdirectory: "Mascots") {
            return bundled
        }
        let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Mascots/\(mascot.rawValue).png")
        return FileManager.default.fileExists(atPath: local.path) ? local : nil
    }

    /// Decodes once into a plain bitmap that the crops share, so drawing a frame never decodes the PNG again.
    private static func decoded(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let side = MascotSpriteLayout.framePixels
        let width = side * MascotSpriteLayout.columns
        let height = side * MascotSpriteLayout.rows
        guard image.width == width, image.height == height,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
