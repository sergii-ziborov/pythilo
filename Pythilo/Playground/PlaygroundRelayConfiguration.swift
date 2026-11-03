import Foundation

/// The relay this build talks to. There is no production domain yet, so an
/// empty `PythiloRelayOrigin` means rooms are unavailable.
enum PlaygroundRelayConfiguration {
    static var origin: URL? {
        #if DEBUG
        // Local development only: -pythiloRelay http://127.0.0.1:3212
        if let value = UserDefaults.standard.string(forKey: "pythiloRelay"), let url = normalized(value, allowsLoopbackHTTP: true) {
            return url
        }
        #endif
        return (Bundle.main.object(forInfoDictionaryKey: "PythiloRelayOrigin") as? String).flatMap { normalized($0) }
    }

    /// An origin is a scheme, host and port only. Plain HTTP only reaches this device.
    static func normalized(_ value: String, allowsLoopbackHTTP: Bool = false) -> URL? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, var parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(),
              let host = parts.host?.lowercased(), !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, parts.path.isEmpty || parts.path == "/" else { return nil }
        guard scheme == "https" || allowsLoopbackHTTP && scheme == "http" && ["127.0.0.1", "localhost", "::1"].contains(host) else { return nil }
        parts.scheme = scheme
        parts.host = host
        parts.path = ""
        if parts.port == (scheme == "https" ? 443 : 80) { parts.port = nil }
        return parts.url
    }

    static func sameOrigin(_ url: URL, _ origin: URL) -> Bool {
        func port(_ value: URL) -> Int { value.port ?? (value.scheme?.lowercased() == "https" ? 443 : 80) }
        return url.scheme?.lowercased() == origin.scheme?.lowercased() && url.host?.lowercased() == origin.host?.lowercased()
            && port(url) == port(origin) && url.user == nil && url.password == nil
    }
}
