import Foundation
import SoundControlCore

/// Asks Anthropic how much of the five-hour window is used, with the login Claude Code already has on this Mac.
///
/// The access token is read the way Claude Code stores it: the `Claude Code-credentials` Keychain item (through
/// `/usr/bin/security`, which that item already trusts, so no Keychain prompt) or `.credentials.json`.
/// The token is only read, never refreshed or written, so Claude Code stays the one that manages the login.
enum ClaudeQuotaClient {
    enum Failure: Error, Equatable {
        case notSignedIn
        case rejected(Int)
        case unreadable
        case offline
    }

    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let keychainService = "Claude Code-credentials"
    private static let timeout: TimeInterval = 10

    static func fetch() async -> Result<ClaudeQuota, Failure> {
        guard let token = await Task.detached(priority: .utility, operation: { accessToken() }).value else {
            return .failure(.notSignedIn)
        }
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("system-controller", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { return .failure(.rejected(status)) }
            guard let quota = ClaudeQuota.parse(data, fileAge: 0, now: Date()) else { return .failure(.unreadable) }
            return .success(quota)
        } catch {
            return .failure(.offline)
        }
    }

    private static func accessToken() -> String? {
        if let fromEnvironment = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"], !fromEnvironment.isEmpty {
            return fromEnvironment
        }
        let keychain = TerminalDelivery.run("/usr/bin/security", ["find-generic-password", "-s", keychainService, "-w"])
        if let token = keychain.flatMap({ token(inCredentials: Data($0.utf8)) }) { return token }
        return (try? Data(contentsOf: ClaudePaths.credentials)).flatMap(token(inCredentials:))
    }

    private static func token(inCredentials data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        return token
    }
}

extension ClaudeQuotaClient.Failure {
    var message: String {
        switch self {
        case .notSignedIn: "Sign in to Claude Code on this Mac (run `claude` once) to read your usage."
        case .rejected(401), .rejected(403): "Claude Code's login has expired. Open any Claude Code session to renew it."
        case .rejected(429): "Anthropic is rate limiting the usage check. It retries by itself."
        case .rejected(let status): "The usage check failed (HTTP \(status)). It retries by itself."
        case .unreadable: "The usage answer had no five-hour window."
        case .offline: "Could not reach Anthropic to read usage. It retries by itself."
        }
    }
}
