import AppKit
import SwiftUI
import SoundControlCore

/// Renders every animal as a strip of frames with the app's own painters, for the Windows companion
/// (`windows/syscontrol/sprites`). Run from a layout-check script: `do:export-sprites`.
@MainActor
enum MascotSpriteExport {
    static let frameSide: Double = 128
    static let walkFrames = 8
    /// Strip order: walk 0..<8, rest, held, fall.
    static func export(to folder: URL) -> [String] {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return Mascot.animals.compactMap { mascot in
            let frames = poses().map { render(mascot, pose: $0.pose, face: $0.face) }
            guard let strip = join(frames), let png = strip.representation(using: .png, properties: [:]) else {
                return nil
            }
            let url = folder.appendingPathComponent("\(mascot.rawValue).png")
            return (try? png.write(to: url)) == nil ? nil : url.lastPathComponent
        }
    }

    private static func poses() -> [(pose: MascotPose, face: MascotFace)] {
        let stride = 1.0 / Double(walkFrames)
        let walk = (0..<walkFrames).map { index in
            (MascotPose(x: 0, facesRight: true, isWalking: true, steps: Double(index) * stride, elapsed: 1), MascotFace.calm)
        }
        return walk + [
            (MascotPose(x: 0, facesRight: true, isWalking: false, steps: 0, elapsed: 0.6), .calm),
            (MascotPose(x: 0, facesRight: true, isWalking: false, isPickedUp: true, steps: 0, elapsed: 0.5), .annoyed),
            (MascotPose(x: 0, facesRight: true, isWalking: false, isPickedUp: true, isFlying: true, steps: 0,
                        elapsed: 0.5), .calm)
        ]
    }

    private static func render(_ mascot: Mascot, pose: MascotPose, face: MascotFace) -> NSBitmapImageRep? {
        let cat = MeawkiCatDriver()
        let sheet = MascotSpriteSheet.shared(for: mascot)
        // The cartoon cat eases into its pose; give it a second of frames to get there.
        var drawing = MascotDrawing.make(mascot: mascot, sheet: sheet, cat: cat, pose: pose, face: face, target: nil,
                                         size: frameSide)
        if mascot == .cat {
            let start = Date()
            for frame in 1...24 {
                drawing = cat.drawing(pose: pose, face: face, target: nil, size: frameSide,
                                      now: start.addingTimeInterval(Double(frame) / 24))
            }
        }
        let view = MascotFigure(drawing: drawing, sheet: sheet).frame(width: frameSide, height: frameSide)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.cgImage.map(NSBitmapImageRep.init(cgImage:))
    }

    private static func join(_ frames: [NSBitmapImageRep?]) -> NSBitmapImageRep? {
        let side = Int(frameSide)
        guard let strip = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side * frames.count, pixelsHigh: side,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: strip) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        for (index, frame) in frames.enumerated() {
            frame?.draw(in: NSRect(x: index * side, y: 0, width: side, height: side))
        }
        NSGraphicsContext.restoreGraphicsState()
        return strip
    }
}
