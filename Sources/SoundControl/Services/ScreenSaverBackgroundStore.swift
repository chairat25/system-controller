import AppKit
import ImageIO
import SoundControlCore

/// Manages custom background images and loads the macOS desktop wallpaper, downsampled to keep RAM low.
enum ScreenSaverBackgroundStore {
    static let customImageURL = ConfigStore.applicationSupport().appendingPathComponent("screensaver-background.jpg")
    static let wallpaperCacheURL = ConfigStore.applicationSupport().appendingPathComponent("screensaver-wallpaper.jpg")
    private static let maxPixelSize = 2560
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp", "tif", "tiff"]

    static var hasCustomImage: Bool {
        FileManager.default.isReadableFile(atPath: customImageURL.path)
    }

    enum StoreError: Error, LocalizedError {
        case unreadable
        case decodeFailed
        case encodeFailed

        var errorDescription: String? {
            switch self {
            case .unreadable: "Could not read the selected image file."
            case .decodeFailed: "The selected file is not a supported image."
            case .encodeFailed: "Could not prepare the image for the screen saver."
            }
        }
    }

    /// Validates, downsamples, and saves a custom background photo inside Application Support.
    static func importImage(from sourceURL: URL) throws -> String {
        let values = try? sourceURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values?.isSymbolicLink != true, values?.isRegularFile == true else {
            throw StoreError.unreadable
        }
        let jpegData: Data = try autoreleasepool {
            guard let cgImage = downsizedCGImage(at: sourceURL, maxPixelSize: maxPixelSize) else {
                throw StoreError.decodeFailed
            }
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
                throw StoreError.encodeFailed
            }
            return data
        }
        try FileManager.default.createDirectory(
            at: customImageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jpegData.write(to: customImageURL, options: .atomic)
        let name = sourceURL.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Custom Photo" : String(name.prefix(60))
    }

    static func removeCustomImage() {
        try? FileManager.default.removeItem(at: customImageURL)
    }

    static func loadCustomImage() -> NSImage? {
        guard hasCustomImage else { return nil }
        return loadDownsampledImage(at: customImageURL)
    }

    static func isTCCProtectedPath(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let protectedRoots = [
            "\(home)/Documents",
            "\(home)/Desktop",
            "\(home)/Downloads"
        ]
        return protectedRoots.contains { root in
            path == root || path.hasPrefix("\(root)/")
        }
    }

    static func cacheDesktopWallpaper() {
        let screens = NSScreen.screens
        guard let target = screens.first,
              let url = NSWorkspace.shared.desktopImageURL(for: target) else { return }
        DispatchQueue.global(qos: .utility).async {
            cacheDesktopWallpaper(from: url)
        }
    }

    static func cacheDesktopWallpaper(from sourceURL: URL) {
        guard let resolved = resolveImageFile(at: sourceURL) else { return }
        let jpegData: Data? = autoreleasepool {
            guard let cgImage = downsizedCGImage(at: resolved, maxPixelSize: maxPixelSize) else { return nil }
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        }
        guard let jpegData else { return }
        try? FileManager.default.createDirectory(
            at: wallpaperCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? jpegData.write(to: wallpaperCacheURL, options: .atomic)
    }

    static func loadDesktopWallpaper(at liveURL: URL?) -> NSImage? {
        if let liveURL, isTCCProtectedPath(liveURL) {
            if let cached = loadDownsampledImage(at: wallpaperCacheURL) {
                return cached
            }
        }
        if let liveURL, let liveImage = loadImage(at: liveURL) {
            return liveImage
        }
        return loadDownsampledImage(at: wallpaperCacheURL)
    }

    static func loadDesktopWallpaper(for screen: NSScreen?) -> NSImage? {
        let target = screen ?? NSScreen.main ?? NSScreen.screens.first
        let url = target.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        return loadDesktopWallpaper(at: url)
    }

    static func loadImage(at url: URL) -> NSImage? {
        guard let resolved = resolveImageFile(at: url) else { return nil }
        return loadDownsampledImage(at: resolved)
    }

    static func loadDownsampledImage(at url: URL) -> NSImage? {
        autoreleasepool {
            guard let cgImage = downsizedCGImage(at: url, maxPixelSize: maxPixelSize) else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
    }

    /// If macOS points `desktopImageURL` at a folder (wallpaper rotation), pick the first readable image inside it.
    private static func resolveImageFile(at url: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        if !isDirectory.boolValue { return url }
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
        return items.first { item in
            imageExtensions.contains(item.pathExtension.lowercased())
        }
    }

    private static func downsizedCGImage(at url: URL, maxPixelSize: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
    }
}
