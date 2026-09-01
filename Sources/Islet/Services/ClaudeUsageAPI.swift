import Foundation
import Security

/// The authoritative usage figures, from the endpoint Claude Code's own `/usage`
/// command reads: `GET /api/oauth/usage` on api.anthropic.com.
///
/// Everything Islet derives from transcripts is a fallback for when this is not
/// available — no token, offline, or an expired token. Anything inferred locally
/// is an estimate with real spread in it; this is the number itself, and it
/// carries the server's own reset time, so the window boundary stops being
/// guesswork too.
///
/// The OAuth token comes from the login keychain item Claude Code writes
/// ("Claude Code-credentials"), which macOS gates with its own prompt the first
/// time. It is sent to Anthropic and nowhere else, and is never logged or
/// written to disk.
enum ClaudeUsageAPI {
    struct Window: Equatable {
        /// 0...1
        var utilization: Double
        var resetsAt: Date?
    }

    struct Reading: Equatable {
        var fiveHour: Window?
        var sevenDay: Window?
        var fetchedAt = Date()
    }

    enum Failure: Error, Equatable {
        /// No Claude Code CLI login on this machine.
        case noToken
        /// Logged in once, but the access token has since expired. Claude Code
        /// refreshes it when the CLI runs; a desktop-only install never does.
        case expiredToken
        case unauthorized
        case rateLimited
        case transport

        var explanation: String {
            switch self {
            case .noToken: return "sign in with the claude CLI for exact figures"
            case .expiredToken: return "Claude token expired — run claude to refresh"
            case .unauthorized: return "Claude rejected the token"
            case .rateLimited: return "Claude's usage API is rate limiting"
            case .transport: return "Claude's usage API is unreachable"
            }
        }
    }

    /// Claude Code's own User-Agent matters: without it the endpoint drops the
    /// request into a much tighter rate-limit bucket and answers 429 almost
    /// immediately. Polling stays well inside the safe interval regardless.
    private static let userAgent = "claude-code/2.1.247"
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetch() async -> Result<Reading, Failure> {
        let token: String
        switch tokenState() {
        case .valid(let value): token = value
        case .expired: return .failure(.expiredToken)
        case .missing: return .failure(.noToken)
        }

        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return .failure(.transport) }

        switch http.statusCode {
        case 200: break
        case 401, 403: return .failure(.unauthorized)
        case 429: return .failure(.rateLimited)
        default: return .failure(.transport)
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.transport)
        }
        return .success(Reading(fiveHour: window(object["five_hour"]),
                                sevenDay: window(object["seven_day"])))
    }

    private static func window(_ value: Any?) -> Window? {
        guard let dictionary = value as? [String: Any],
              let utilization = dictionary["utilization"] as? Double
        else { return nil }
        var resets: Date?
        if let text = dictionary["resets_at"] as? String {
            resets = isoWithFraction.date(from: text) ?? isoPlain.date(from: text)
        }
        // The endpoint reports whole percents.
        return Window(utilization: min(max(utilization / 100, 0), 1), resetsAt: resets)
    }

    /// Claude Code writes "Claude Code-credentials", and one suffixed item per
    /// extra account ("Claude Code-credentials-086cd77f"). Only one of them holds
    /// the subscription token, so all of them have to be looked at.
    ///
    /// Names are listed first, without asking for any secret, and only the items
    /// that are Claude's are then read. Enumerating every generic password with
    /// its data would set off an access prompt for unrelated items.
    private static func credentialServices() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let entries = item as? [[String: Any]]
        else { return [] }
        let services = entries.compactMap { $0[kSecAttrService as String] as? String }
            .filter { $0.hasPrefix("Claude Code-credentials") }
        // The unsuffixed item first: it is the one a single-account install uses.
        return Array(Set(services)).sorted { $0.count < $1.count }
    }

    private static func credentials(service: String) -> [String: Any]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["claudeAiOauth"] as? [String: Any]
    }

    /// Explains what was found, for `--diagnose`. Reports the shape of it and
    /// never any part of the secret itself.
    static func tokenStatus() -> String {
        let services = credentialServices()
        guard !services.isEmpty else { return "no Claude Code keychain item found" }
        let described = services.map { service -> String in
            guard let oauth = credentials(service: service) else {
                return "\(service): no claudeAiOauth (holds \(topLevelKeys(service: service)))"
            }
            let present = (oauth["accessToken"] as? String).map { !$0.isEmpty } ?? false
            var when = ""
            if let value = oauth["expiresAt"] as? Double {
                let seconds = value > 1_000_000_000_000 ? value / 1000 : value
                let date = Date(timeIntervalSince1970: seconds)
                let formatter = DateFormatter()
                formatter.dateFormat = "d MMM HH:mm"
                when = ", \(expired(oauth) ? "expired" : "valid until") \(formatter.string(from: date))"
            }
            let refresh = (oauth["refreshToken"] as? String).map { !$0.isEmpty } ?? false
            return "\(service): token \(present ? "present" : "missing")\(when)"
                + ", refresh token \(refresh ? "present" : "missing")"
        }
        return described.joined(separator: " | ")
    }

    /// Key names only — used to explain an unexpected keychain layout.
    private static func topLevelKeys(service: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
            return "unreadable, OSStatus \(status): \(reason)"
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "\(data.count) bytes, not JSON"
        }
        return object.keys.sorted().joined(separator: ", ")
    }

    private static func expired(_ oauth: [String: Any]) -> Bool {
        guard let value = oauth["expiresAt"] as? Double else { return false }
        let seconds = value > 1_000_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds) < Date()
    }

    private enum TokenState {
        case missing
        case expired
        case valid(String)
    }

    /// Reads the token Claude Code stored. Never logged, never copied anywhere.
    /// Distinguishes "never signed in" from "signed in, token has aged out",
    /// because the fix for each is different and worth telling the user.
    private static func tokenState() -> TokenState {
        var sawExpired = false
        for service in credentialServices() {
            guard let oauth = credentials(service: service),
                  let token = oauth["accessToken"] as? String, !token.isEmpty
            else { continue }
            // An expired token only earns a 401; skip the round trip.
            if expired(oauth) {
                sawExpired = true
                continue
            }
            return .valid(token)
        }
        return sawExpired ? .expired : .missing
    }
}

nonisolated(unsafe) private let isoWithFraction: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

nonisolated(unsafe) private let isoPlain: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()
