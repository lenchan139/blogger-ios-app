import Foundation

/// A pluggable source of the OAuth 2.0 access token used to authorize requests.
/// `AuthManager` provides this; tests can inject a stub.
protocol AccessTokenProvider {
    func currentAccessToken() async throws -> String
}

/// Thin, async REST client for the Blogger API v3.
/// Docs: https://developers.google.com/blogger/docs/3.0
final class BloggerClient {
    static let baseURL = URL(string: "https://www.googleapis.com/blogger/v3")!

    private let session: URLSession
    private let tokenProvider: AccessTokenProvider

    init(
        session: URLSession = .shared,
        tokenProvider: AccessTokenProvider = AuthManager.shared
    ) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    // MARK: - Users

    func getUser() async throws -> BloggerUser {
        try await request(path: "/users/self")
    }

    // MARK: - Blogs

    func listUserBlogs() async throws -> BlogList {
        try await request(path: "/users/self/blogs")
    }

    func getBlog(_ blogId: String) async throws -> Blog {
        try await request(path: "/blogs/\(blogId)")
    }

    func getBlogUserInfo(_ blogId: String) async throws -> BlogUserInfo {
        try await request(path: "/users/self/blogs/\(blogId)")
    }

    // MARK: - Posts

    func listPosts(blogId: String, pageToken: String? = nil, fetchBodies: Bool = true, status: String? = nil) async throws -> PostList {
        var query: [String: String] = ["fetchBodies": fetchBodies ? "true" : "false"]
        if let pageToken { query["pageToken"] = pageToken }
        if let status { query["status"] = status }
        return try await request(path: "/blogs/\(blogId)/posts", query: query)
    }

    func getPost(blogId: String, postId: String, fetchBodies: Bool = true) async throws -> Post {
        try await request(path: "/blogs/\(blogId)/posts/\(postId)", query: ["fetchBodies": fetchBodies ? "true" : "false"])
    }

    func searchPosts(blogId: String, query: String, pageToken: String? = nil) async throws -> PostList {
        var q = ["q": query]
        if let pageToken { q["pageToken"] = pageToken }
        return try await request(path: "/blogs/\(blogId)/posts/search", query: q)
    }

    func insertPost(_ post: Post, blogId: String, isDraft: Bool = false) async throws -> Post {
        try await request(path: "/blogs/\(blogId)/posts", method: "POST", query: ["isDraft": isDraft ? "true" : "false"], body: post)
    }

    func updatePost(_ post: Post, blogId: String) async throws -> Post {
        try await request(path: "/blogs/\(blogId)/posts/\(post.id)", method: "PUT", body: post)
    }

    func patchPost(_ post: Post, blogId: String) async throws -> Post {
        try await request(path: "/blogs/\(blogId)/posts/\(post.id)", method: "PATCH", body: post)
    }

    func deletePost(blogId: String, postId: String) async throws {
        try await request(path: "/blogs/\(blogId)/posts/\(postId)", method: "DELETE")
    }

    func publishPost(blogId: String, postId: String) async throws -> Post {
        try await request(path: "/blogs/\(blogId)/posts/\(postId)/publish", method: "POST")
    }

    func revertPost(blogId: String, postId: String) async throws -> Post {
        try await request(path: "/blogs/\(blogId)/posts/\(postId)/revert", method: "POST")
    }

    // MARK: - Pages

    func listPages(blogId: String, pageToken: String? = nil) async throws -> PageList {
        var query: [String: String] = [:]
        if let pageToken { query["pageToken"] = pageToken }
        return try await request(path: "/blogs/\(blogId)/pages", query: query)
    }

    func getPage(blogId: String, pageId: String) async throws -> Page {
        try await request(path: "/blogs/\(blogId)/pages/\(pageId)")
    }

    func insertPage(_ page: Page, blogId: String) async throws -> Page {
        try await request(path: "/blogs/\(blogId)/pages", method: "POST", body: page)
    }

    func updatePage(_ page: Page, blogId: String) async throws -> Page {
        try await request(path: "/blogs/\(blogId)/pages/\(page.id)", method: "PUT", body: page)
    }

    func deletePage(blogId: String, pageId: String) async throws {
        try await request(path: "/blogs/\(blogId)/pages/\(pageId)", method: "DELETE")
    }

    // MARK: - PageViews

    func getPageViews(blogId: String, range: String? = nil) async throws -> PageViews {
        var query: [String: String] = [:]
        if let range { query["range"] = range }
        return try await request(path: "/blogs/\(blogId)/pageviews", query: query)
    }

    // MARK: - Comments

    func listComments(blogId: String, postId: String, pageToken: String? = nil) async throws -> CommentList {
        var query: [String: String] = [:]
        if let pageToken { query["pageToken"] = pageToken }
        return try await request(path: "/blogs/\(blogId)/posts/\(postId)/comments", query: query)
    }

    func listCommentsByBlog(blogId: String, pageToken: String? = nil) async throws -> CommentList {
        var query: [String: String] = [:]
        if let pageToken { query["pageToken"] = pageToken }
        return try await request(path: "/blogs/\(blogId)/comments", query: query)
    }

    func deleteComment(blogId: String, postId: String, commentId: String) async throws {
        try await request(path: "/blogs/\(blogId)/posts/\(postId)/comments/\(commentId)", method: "DELETE")
    }

    func approveComment(blogId: String, postId: String, commentId: String) async throws -> Comment {
        try await request(path: "/blogs/\(blogId)/posts/\(postId)/comments/\(commentId)/approve", method: "POST")
    }

    func markCommentAsSpam(blogId: String, postId: String, commentId: String) async throws -> Comment {
        try await request(path: "/blogs/\(blogId)/posts/\(postId)/comments/\(commentId)/spam", method: "POST")
    }

    func removeCommentContent(blogId: String, postId: String, commentId: String) async throws -> Comment {
        try await request(path: "/blogs/\(blogId)/posts/\(postId)/comments/\(commentId)/removecontent", method: "POST")
    }

    // MARK: - Generic request

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        query: [String: String]? = nil,
        body: (any Encodable)? = nil
    ) async throws -> T {
        let token = try await tokenProvider.currentAccessToken()

        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if let query {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw BloggerError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BloggerError.emptyResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = try? JSONDecoder()
                .decode(GoogleAPIErrorResponse.self, from: data)
                .error?.message
            throw BloggerError.http(statusCode: http.statusCode, message: message)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw BloggerError.decoding(error)
        }
    }

    private func request(
        path: String,
        method: String = "GET",
        query: [String: String]? = nil,
        body: (any Encodable)? = nil
    ) async throws {
        let token = try await tokenProvider.currentAccessToken()

        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if let query {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw BloggerError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BloggerError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BloggerError.http(statusCode: http.statusCode, message: nil)
        }
    }
}

/// Standard Google API error envelope.
struct GoogleAPIErrorResponse: Codable {
    struct ErrorBody: Codable {
        let code: Int?
        let message: String?
        let status: String?
    }

    let error: ErrorBody?
}

/// Type-erases any `Encodable` so an optional body parameter can accept a
/// concrete type at the call site while defaulting to `nil`.
struct AnyEncodable: Encodable {
    private let encodable: any Encodable
    init(_ encodable: any Encodable) { self.encodable = encodable }
    func encode(to encoder: Encoder) throws { try encodable.encode(to: encoder) }
}
