import Foundation

public struct GitHubRepository: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let fullName: String
    public let defaultBranch: String
    public let cloneURL: URL
    public let htmlURL: URL
    public let isPrivate: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case defaultBranch = "default_branch"
        case cloneURL = "clone_url"
        case htmlURL = "html_url"
        case isPrivate = "private"
    }
}

public enum GitHubError: Error, CustomStringConvertible {
    case unauthorized
    case forbidden
    case offline
    case http(Int)
    case invalidResponse

    public var description: String {
        switch self {
        case .unauthorized: "The token was rejected (401)."
        case .forbidden: "The token has no access (403)."
        case .offline: "You're offline."
        case .http(let code): "GitHub answered with HTTP \(code)."
        case .invalidResponse: "Unexpected answer from GitHub."
        }
    }
}

/// The few GitHub REST calls Tide needs. Everything else goes through git over HTTPS.
public struct GitHubClient: Sendable {
    private let token: String
    private let session: URLSession

    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    /// Repositories the token can access. With a fine-grained token limited to one repository this is usually one entry.
    public func accessibleRepositories() async throws -> [GitHubRepository] {
        var request = URLRequest(url: URL(string: "https://api.github.com/user/repos?per_page=100&sort=updated")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw GitHubError.offline
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse else { throw GitHubError.invalidResponse }
        switch http.statusCode {
        case 200: return try JSONDecoder().decode([GitHubRepository].self, from: data)
        case 401: throw GitHubError.unauthorized
        case 403: throw GitHubError.forbidden
        default: throw GitHubError.http(http.statusCode)
        }
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut,
        .cannotFindHost, .cannotConnectToHost, .dataNotAllowed,
    ]
}
