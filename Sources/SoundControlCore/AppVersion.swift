import Foundation

/// Semantic version (`major.minor.patch`) used for comparing app releases.
public struct AppVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `"v1.3.1"`, `"1.3.1"`, or `"1.3"` into an `AppVersion`.
    public init?(parsing raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed
        let core = cleaned.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? cleaned
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 && parts.count <= 3 else { return nil }
        guard let major = Int(parts[0]),
              let minor = Int(parts[1]),
              major >= 0, minor >= 0 else { return nil }
        let patch: Int
        if parts.count == 3 {
            guard let p = Int(parts[2]), p >= 0 else { return nil }
            patch = p
        } else {
            patch = 0
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

/// Metadata for a GitHub release of System Controller.
public struct ReleaseAssetInfo: Equatable, Sendable {
    public let version: AppVersion
    public let tagName: String
    public let htmlURL: URL?
    public let zipName: String
    public let zipURL: URL
    public let checksumURL: URL

    public init(
        version: AppVersion,
        tagName: String,
        htmlURL: URL?,
        zipName: String,
        zipURL: URL,
        checksumURL: URL
    ) {
        self.version = version
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.zipName = zipName
        self.zipURL = zipURL
        self.checksumURL = checksumURL
    }

    /// Parses GitHub `/repos/<repo>/releases/latest` JSON payload.
    public static func parseLatestRelease(
        from data: Data,
        repo: String = "chairat25/system-controller"
    ) -> ReleaseAssetInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagRaw = json["tag_name"] as? String else { return nil }
        if let draft = json["draft"] as? Bool, draft { return nil }
        if let prerelease = json["prerelease"] as? Bool, prerelease { return nil }
        guard let version = AppVersion(parsing: tagRaw) else { return nil }

        let versionString = version.description
        let zipName = "SystemController-\(versionString).zip"
        let shaName = "SystemController-\(versionString).sha256"
        let baseDownload = "https://github.com/\(repo)/releases/download/\(tagRaw)"

        var resolvedZipURL: URL?
        var resolvedShaURL: URL?
        if let assets = json["assets"] as? [[String: Any]] {
            for asset in assets {
                guard let name = asset["name"] as? String,
                      let urlStr = asset["browser_download_url"] as? String,
                      let url = URL(string: urlStr) else { continue }
                if name == zipName { resolvedZipURL = url }
                if name == shaName { resolvedShaURL = url }
            }
        }

        guard let zipURL = resolvedZipURL ?? URL(string: "\(baseDownload)/\(zipName)"),
              let checksumURL = resolvedShaURL ?? URL(string: "\(baseDownload)/\(shaName)") else {
            return nil
        }
        let htmlURL = (json["html_url"] as? String).flatMap(URL.init(string:))
        return ReleaseAssetInfo(
            version: version,
            tagName: tagRaw,
            htmlURL: htmlURL,
            zipName: zipName,
            zipURL: zipURL,
            checksumURL: checksumURL
        )
    }

    /// Extracts the expected lowercase 64-character SHA-256 hex digest from a `.sha256` file.
    public static func expectedSHA256(for fileName: String, in checksumFileContent: String) -> String? {
        for line in checksumFileContent.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(whereSeparator: \.isWhitespace)
            guard let hashCandidate = parts.first.map(String.init)?.lowercased(),
                  hashCandidate.count == 64,
                  hashCandidate.allSatisfy({ $0.isHexDigit }) else { continue }
            if parts.count == 1 {
                return hashCandidate
            }
            let target = parts.dropFirst().joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "* "))
            if target == fileName || target.hasSuffix("/\(fileName)") {
                return hashCandidate
            }
        }
        return nil
    }
}
