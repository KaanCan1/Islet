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
        /// The access token had aged out and renewing it did not go through.
        /// Transient — the next poll tries again.
        case renewFailed
        /// The sign-in itself is over: the refresh token is spent or expired,
        /// and only a fresh `claude` login can fix it.
        case reauthRequired
        case unauthorized
        case rateLimited
        case transport

        var explanation: String {
            switch self {
            case .noToken: return "sign in with the claude CLI for exact figures"
            case .renewFailed: return "renewing the Claude token failed — retrying"
            case .reauthRequired: return "Claude sign-in expired — run claude to sign in"
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
    private static let ownAgent = "Islet/"
        + ((Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.0")
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// The OAuth client Claude Code identifies itself as, and the endpoint that
    /// trades a refresh token for a fresh access token. Access tokens last well
    /// under a day, so without renewing them here a desktop-only install goes
    /// back to guessing every morning.
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let tokenEndpoint = URL(string: "https://platform.claude.com/v1/oauth/token")!
    /// Only used when the stored item lists none; normally its own scopes are
    /// echoed back, so a renewal never quietly narrows what the token can do.
    private static let defaultScopes = [
        "user:profile", "user:inference", "user:sessions:claude_code",
        "user:mcp_servers", "user:file_upload"
    ]

    static func fetch() async -> Result<Reading, Failure> {
        let token: String
        switch tokenState() {
        case .valid(let value):
            token = value
        case .expired(let service, let blob):
            switch await renew(service: service, blob: blob) {
            case .success(let value): token = value
            case .failure(let failure): return .failure(failure)
            }
        case .missing:
            return .failure(.noToken)
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

    /// The whole stored document, not just Claude's slice of it. Renewing writes
    /// the item back, and anything else living alongside has to survive that.
    private static func credentialBlob(service: String) -> [String: Any]? {
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
        return object
    }

    private static func credentials(service: String) -> [String: Any]? {
        credentialBlob(service: service)?["claudeAiOauth"] as? [String: Any]
    }

    /// Writes the document back in place. SecItemUpdate rather than delete-then-add
    /// on purpose: it keeps the item's access control list, so neither Claude Code
    /// nor Islet is asked for keychain permission again afterwards.
    private static func store(_ blob: [String: Any], service: String) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: blob) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        return SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecSuccess
    }

    /// Trades the refresh token for a new access token and writes the pair back
    /// where Claude Code keeps it.
    ///
    /// Writing back is not optional. The endpoint rotates the refresh token, so
    /// keeping the new one to ourselves would leave the CLI holding a spent one
    /// and log the user out of Claude Code. On a write failure the fresh token is
    /// still returned, so this poll succeeds even though the next one repeats the
    /// work.
    private static func renew(service: String, blob: [String: Any]) async -> Result<String, Failure> {
        guard let oauth = blob["claudeAiOauth"] as? [String: Any],
              let refreshToken = oauth["refreshToken"] as? String, !refreshToken.isEmpty,
              !expired(oauth, key: "refreshTokenExpiresAt")
        else { return .failure(.reauthRequired) }

        // A rejected renewal must not turn into a request per poll.
        if let last = lastRenewFailure, Date().timeIntervalSince(last) < renewCooldown {
            return .failure(.renewFailed)
        }

        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Islet's own name, unlike the usage endpoint, which wants Claude Code's.
        // This one throttles "claude-code/*" to a flat 429 — the CLI never sends
        // that here, since its own refresh goes out under its HTTP client's
        // agent — so borrowing the name would only get us rate limited.
        request.setValue(ownAgent, forHTTPHeaderField: "User-Agent")
        // `scope` is required. Claude Code sends the scopes it asked for, and a
        // request without them does not come back as a 400 — it earns a blanket
        // 429, which reads exactly like being rate limited.
        let scopes = (oauth["scopes"] as? [String]).flatMap { $0.isEmpty ? nil : $0 } ?? defaultScopes
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "scope": scopes.joined(separator: " ")
        ])
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else {
            lastRenewFailure = Date()
            lastRenewDetail = "no response from \(tokenEndpoint.host ?? "endpoint")"
            return .failure(.renewFailed)
        }

        guard http.statusCode == 200,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = payload["access_token"] as? String, !access.isEmpty
        else {
            lastRenewFailure = Date()
            lastRenewDetail = "HTTP \(http.statusCode): "
                + (String(data: data.prefix(200), encoding: .utf8) ?? "unreadable body")
            // 400/401 means this refresh token is spent. Claude Code rotating it
            // a moment ago looks exactly the same, so before declaring the login
            // dead, look again at what is stored: a valid token there means the
            // CLI won the race and there is nothing to report.
            guard (400...401).contains(http.statusCode) else { return .failure(.renewFailed) }
            if case .valid(let current) = tokenState() {
                lastRenewFailure = nil
                lastRenewDetail = nil
                return .success(current)
            }
            return .failure(.reauthRequired)
        }

        lastRenewFailure = nil
        lastRenewDetail = nil
        var renewed = oauth
        renewed["accessToken"] = access
        // Both are optional in the response; an absent one means keep what we had.
        if let rotated = payload["refresh_token"] as? String, !rotated.isEmpty {
            renewed["refreshToken"] = rotated
        }
        let now = Date().timeIntervalSince1970
        if let lifetime = payload["expires_in"] as? Double {
            renewed["expiresAt"] = (now + lifetime) * 1000
        }
        if let lifetime = payload["refresh_token_expires_in"] as? Double {
            renewed["refreshTokenExpiresAt"] = (now + lifetime) * 1000
        }
        if let granted = payload["scope"] as? String, !granted.isEmpty {
            renewed["scopes"] = granted.split(separator: " ").map(String.init)
        }
        // Held onto whether or not the write lands. A refused write would
        // otherwise send every later poll back to the endpoint, rotating the
        // refresh token again and again while Claude Code still holds the first
        // one — which is precisely how a working CLI login gets broken.
        cached = (access, Date(timeIntervalSince1970:
            ((renewed["expiresAt"] as? Double) ?? 0) / 1000))

        var updated = blob
        updated["claudeAiOauth"] = renewed
        if !store(updated, service: service) {
            lastRenewDetail = "keychain write refused — token held in memory only"
        }
        return .success(access)
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

    /// Timestamps are milliseconds in this document; tolerate seconds anyway.
    /// A missing timestamp is treated as still valid — the endpoint is the real
    /// authority, and guessing "expired" would renew a perfectly good token.
    private static func expired(_ oauth: [String: Any], key: String = "expiresAt") -> Bool {
        guard let value = oauth[key] as? Double else { return false }
        let seconds = value > 1_000_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds) < Date()
    }

    private enum TokenState {
        case missing
        case expired(service: String, blob: [String: Any])
        case valid(String)
    }

    /// The last token this process minted, so a keychain write that did not take
    /// cannot turn into a renewal per poll. Process-local and never written down.
    nonisolated(unsafe) private static var cached: (value: String, expires: Date)?
    nonisolated(unsafe) private static var lastRenewFailure: Date?
    private static let renewCooldown: TimeInterval = 300
    /// Why the last renewal did not go through, for `--diagnose`. Status and the
    /// server's error type only — never any part of the request.
    nonisolated(unsafe) static var lastRenewDetail: String?

    /// Reads the token Claude Code stored. Never logged, never copied anywhere.
    /// Distinguishes "never signed in" from "signed in, token has aged out",
    /// because the fix for each is different: the second one this can repair
    /// itself, and carries out the item it has to write back to.
    private static func tokenState() -> TokenState {
        var stale: (service: String, blob: [String: Any])?
        for service in credentialServices() {
            guard let blob = credentialBlob(service: service),
                  let oauth = blob["claudeAiOauth"] as? [String: Any],
                  let token = oauth["accessToken"] as? String, !token.isEmpty
            else { continue }
            // An expired token only earns a 401; renew instead of spending a
            // round trip on it.
            if expired(oauth) {
                if stale == nil { stale = (service, blob) }
                continue
            }
            return .valid(token)
        }
        guard let stale else { return .missing }
        // Only consulted once what is stored has aged out, so a token Claude Code
        // renewed in the meantime still wins over ours.
        if let cached, cached.expires > Date() { return .valid(cached.value) }
        return .expired(service: stale.service, blob: stale.blob)
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
