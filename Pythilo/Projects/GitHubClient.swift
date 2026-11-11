import Foundation
import PythiloGit

/// A repository as GitHub's REST API describes it, for searching and picking what to clone.
struct GitHubRepository: Decodable, Identifiable, Hashable, Sendable {
    struct Owner: Decodable, Hashable, Sendable {
        let login: String
        let avatarURL: URL?
        enum CodingKeys: String, CodingKey { case login, avatarURL = "avatar_url" }
    }

    let id: Int
    let name: String
    let fullName: String
    let summary: String?
    let stars: Int
    let forks: Int
    let language: String?
    let isPrivate: Bool
    let isFork: Bool
    let isArchived: Bool
    let cloneURL: String
    let webURL: URL?
    let updated: Date?
    let owner: Owner

    enum CodingKeys: String, CodingKey {
        case id, name, language, owner
        case fullName = "full_name", summary = "description", stars = "stargazers_count", forks = "forks_count"
        case isPrivate = "private", isFork = "fork", isArchived = "archived", cloneURL = "clone_url"
        case webURL = "html_url", updated = "pushed_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        fullName = try c.decode(String.self, forKey: .fullName)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        stars = try c.decodeIfPresent(Int.self, forKey: .stars) ?? 0
        forks = try c.decodeIfPresent(Int.self, forKey: .forks) ?? 0
        language = try c.decodeIfPresent(String.self, forKey: .language)
        isPrivate = try c.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        isFork = try c.decodeIfPresent(Bool.self, forKey: .isFork) ?? false
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        cloneURL = try c.decode(String.self, forKey: .cloneURL)
        webURL = try c.decodeIfPresent(URL.self, forKey: .webURL)
        updated = try c.decodeIfPresent(Date.self, forKey: .updated)
        owner = try c.decode(Owner.self, forKey: .owner)
    }
}

struct GitHubUser: Decodable, Sendable {
    let login: String
    let name: String?
    let email: String?
    let avatarURL: URL?
    let publicRepos: Int?
    let privateRepos: Int?

    enum CodingKeys: String, CodingKey {
        case login, name, email
        case avatarURL = "avatar_url", publicRepos = "public_repos", privateRepos = "total_private_repos"
    }
}

enum GitHubSort: String, CaseIterable, Identifiable, Sendable {
    case stars, updated, best
    var id: String { rawValue }
    var title: String {
        switch self {
        case .stars: "Most stars"
        case .updated: "Recently updated"
        case .best: "Best match"
        }
    }
}

/// The GitHub REST API, read only. The account token lives in the Keychain (GitCredentialVault)
/// and goes only to api.github.com; nothing else about the person is sent.
enum GitHubClient {
    static let host = "https://github.com"
    private static let api = URL(string: "https://api.github.com")!

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The saved account, if the person signed in from Settings.
    static var credential: GitCredential? { GitCredentialVault.credential(for: host) }
    static var token: String? { GitCredentialVault.token(for: host) }

    static func search(_ text: String, sort: GitHubSort, page: Int = 1, token: String? = token) async throws -> (total: Int, items: [GitHubRepository]) {
        struct Page: Decodable { let total_count: Int; let items: [GitHubRepository] }
        var components = URLComponents(url: api.appending(path: "search/repositories"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "per_page", value: "30"),
            URLQueryItem(name: "page", value: String(page)),
        ] + (sort == .best ? [] : [URLQueryItem(name: "sort", value: sort.rawValue), URLQueryItem(name: "order", value: "desc")])
        let result: Page = try await get(components.url!, token: token)
        return (result.total_count, result.items)
    }

    /// Every repository the account owns or works on, private ones included, newest first.
    static func repositories(token: String) async throws -> [GitHubRepository] {
        var all: [GitHubRepository] = []
        for page in 1...5 {
            var components = URLComponents(url: api.appending(path: "user/repos"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "sort", value: "pushed"),
                URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member"),
            ]
            let batch: [GitHubRepository] = try await get(components.url!, token: token)
            all += batch
            if batch.count < 100 { break }
        }
        return all
    }

    static func user(token: String) async throws -> GitHubUser {
        try await get(api.appending(path: "user"), token: token)
    }

    private static func get<T: Decodable>(_ url: URL, token: String?) async throws -> T {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Pythilo", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure(message: "GitHub could not be reached. Check the connection and try again.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do { return try decoder.decode(T.self, from: data) } catch {
                throw Failure(message: "GitHub answered in an unexpected form.")
            }
        case 401:
            throw Failure(message: "GitHub did not accept the token. Sign in again in Settings › GitHub account.")
        case 403, 429:
            throw Failure(message: token == nil
                ? "GitHub's search limit for apps without an account was reached. Wait a minute, or sign in to GitHub in Settings for a higher limit."
                : "GitHub's rate limit was reached. Wait a minute and try again.")
        case 422:
            throw Failure(message: "GitHub could not search for that. Try other words.")
        default:
            throw Failure(message: "GitHub answered with error \(status).")
        }
    }
}
