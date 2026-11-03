import Foundation

/// `<origin>/playground/room/<id>/#key=…&access=…&expires=…&mode=edit|view`, or the
/// same path under `pythilo://`. The key and capability stay in the fragment, which
/// is never sent over HTTP.
struct PlaygroundLink: Equatable, Sendable {
    let id: String
    let key: String
    let access: String
    let expiresAt: Date
    let isReadOnly: Bool

    static func parse(_ raw: String, origin: URL? = PlaygroundRelayConfiguration.origin) throws -> PlaygroundLink {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)), url.user == nil, url.password == nil else { throw LinkError.invalid }
        let path: String
        switch url.scheme?.lowercased() {
        case "pythilo":
            guard url.host?.lowercased() == "playground" else { throw LinkError.invalid }
            path = "/playground" + url.path
        case "https", "http":
            guard let origin, PlaygroundRelayConfiguration.sameOrigin(url, origin) else { throw LinkError.otherOrigin }
            path = url.path
        default:
            throw LinkError.invalid
        }
        let parts = path.split(separator: "/")
        guard parts.count == 3, parts[0] == "playground", parts[1] == "room", valid(String(parts[2]), count: 24), let fragment = url.fragment,
              let parameters = URLComponents(string: "https://pythilo.invalid/?" + fragment)?.queryItems else { throw LinkError.invalid }
        func value(_ name: String) -> String? { parameters.first { $0.name == name }?.value }
        guard let key = value("key"), valid(key, count: 43), let access = value("access"), valid(access, count: 43),
              let time = value("expires").flatMap(Double.init), time.isFinite, time > 0, time <= 9_007_199_254_740_991, time.rounded() == time,
              ["edit", "view", nil].contains(value("mode")) else { throw LinkError.invalid }
        return PlaygroundLink(id: String(parts[2]), key: key, access: access, expiresAt: Date(timeIntervalSince1970: time / 1000), isReadOnly: value("mode") == "view")
    }

    func url(origin: URL) -> URL {
        var parts = URLComponents(url: origin, resolvingAgainstBaseURL: false)!
        parts.path = "/playground/room/\(id)/"
        parts.percentEncodedFragment = fragment
        return parts.url!
    }

    var appURL: URL {
        var parts = URLComponents(string: "pythilo://playground/room/\(id)/")!
        parts.percentEncodedFragment = fragment
        return parts.url!
    }

    func readOnly(access: String) -> PlaygroundLink {
        PlaygroundLink(id: id, key: key, access: access, expiresAt: expiresAt, isReadOnly: true)
    }

    private var fragment: String? {
        var fragment = URLComponents()
        fragment.queryItems = [
            URLQueryItem(name: "key", value: key), URLQueryItem(name: "access", value: access),
            URLQueryItem(name: "expires", value: String(Int64(expiresAt.timeIntervalSince1970 * 1000))),
            URLQueryItem(name: "mode", value: isReadOnly ? "view" : "edit"),
        ]
        return fragment.percentEncodedQuery
    }

    private static func valid(_ value: String, count: Int) -> Bool {
        value.utf8.count == count && value.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }
    }

    enum LinkError: LocalizedError, Equatable {
        case invalid, otherOrigin
        var errorDescription: String? {
            switch self {
            case .invalid: "Paste a complete Pythilo room link, including everything after #."
            case .otherOrigin: "This link is for a different relay than the one this app uses."
            }
        }
    }
}
