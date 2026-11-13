import Foundation
import Testing
@testable import SoundControlCore

@Suite("Auto-update versioning and release parsing")
struct AutoUpdateTests {
    @Test("parses semantic versions with or without leading v")
    func parsesVersions() throws {
        let v1 = try #require(AppVersion(parsing: "v1.3.1"))
        #expect(v1 == AppVersion(major: 1, minor: 3, patch: 1))
        #expect(v1.description == "1.3.1")

        let v2 = try #require(AppVersion(parsing: "2.4"))
        #expect(v2 == AppVersion(major: 2, minor: 4, patch: 0))

        #expect(AppVersion(parsing: "") == nil)
        #expect(AppVersion(parsing: "dev") == nil)
        #expect(AppVersion(parsing: "1") == nil)
    }

    @Test("compares semantic versions across major, minor and patch")
    func comparesVersions() throws {
        let v131 = try #require(AppVersion(parsing: "1.3.1"))
        let v132 = try #require(AppVersion(parsing: "1.3.2"))
        let v139 = try #require(AppVersion(parsing: "1.3.9"))
        let v140 = try #require(AppVersion(parsing: "v1.4.0"))
        let v200 = try #require(AppVersion(parsing: "2.0.0"))

        #expect(v131 < v132)
        #expect(v132 < v139)
        #expect(v139 < v140)
        #expect(v140 < v200)
        #expect(!(v131 < v131))
    }

    @Test("parses GitHub latest release payload and skips drafts or prereleases")
    func parsesReleaseJSON() throws {
        let json = """
        {
          "tag_name": "v1.4.0",
          "draft": false,
          "prerelease": false,
          "html_url": "https://github.com/chairat25/system-controller/releases/tag/v1.4.0",
          "assets": [
            {
              "name": "SystemController-1.4.0.zip",
              "browser_download_url": "https://github.com/chairat25/system-controller/releases/download/v1.4.0/SystemController-1.4.0.zip"
            },
            {
              "name": "SystemController-1.4.0.sha256",
              "browser_download_url": "https://github.com/chairat25/system-controller/releases/download/v1.4.0/SystemController-1.4.0.sha256"
            }
          ]
        }
        """
        let release = try #require(ReleaseAssetInfo.parseLatestRelease(from: Data(json.utf8)))
        #expect(release.version == AppVersion(major: 1, minor: 4, patch: 0))
        #expect(release.zipName == "SystemController-1.4.0.zip")
        #expect(release.zipURL.lastPathComponent == "SystemController-1.4.0.zip")
        #expect(release.checksumURL.lastPathComponent == "SystemController-1.4.0.sha256")

        let draft = #"{"tag_name":"v1.5.0","draft":true,"prerelease":false}"#
        #expect(ReleaseAssetInfo.parseLatestRelease(from: Data(draft.utf8)) == nil)

        let prerelease = #"{"tag_name":"v1.5.0","draft":false,"prerelease":true}"#
        #expect(ReleaseAssetInfo.parseLatestRelease(from: Data(prerelease.utf8)) == nil)
    }

    @Test("extracts matching SHA-256 digest from shasum file")
    func extractsChecksum() {
        let dmgHash = String(repeating: "a", count: 64)
        let zipHash = String(repeating: "b", count: 64)
        let content = """
        \(dmgHash)  SystemController-1.4.0.dmg
        \(zipHash)  SystemController-1.4.0.zip
        """
        #expect(ReleaseAssetInfo.expectedSHA256(for: "SystemController-1.4.0.zip", in: content) == zipHash)
        #expect(ReleaseAssetInfo.expectedSHA256(for: "SystemController-1.4.0.dmg", in: content) == dmgHash)
        #expect(ReleaseAssetInfo.expectedSHA256(for: "Other.zip", in: content) == nil)
    }

    @Test("AppSettings enables auto-update by default and decodes legacy JSON safely")
    func appSettingsAutoUpdate() throws {
        #expect(AppSettings.default.autoUpdateEnabled == true)
        let disabled = AppSettings.default.withAutoUpdate(false)
        #expect(disabled.autoUpdateEnabled == false)

        let decodedDisabled = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(disabled))
        #expect(decodedDisabled.autoUpdateEnabled == false)

        // Existing config JSON without `autoUpdateEnabled` must still decode with true as default.
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"popupShortcut":null}"#.utf8))
        #expect(legacy.autoUpdateEnabled == true)
        #expect(legacy == .default)
    }
}
