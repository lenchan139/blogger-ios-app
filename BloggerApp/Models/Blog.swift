import Foundation

/// Base metadata shared by most Blogger resources.
struct BloggerObject: Codable {
    let kind: String?
    let id: String?
    let selfLink: String?
}

/// A user's blog (`blogger#blog`).
struct Blog: Codable, Identifiable {
    let kind: String
    let id: String
    let name: String?
    let description: String?
    let published: String?
    let updated: String?
    let url: String?
    let selfLink: String?
    let posts: CountInfo?
    let pages: CountInfo?
    let locale: LocaleInfo?

    struct CountInfo: Codable {
        let totalItems: Int?
        let selfLink: String?
    }

    struct LocaleInfo: Codable {
        let language: String?
        let country: String?
        let variant: String?
    }
}

/// Wrapper for the blogs list endpoint.
struct BlogList: Codable {
    let kind: String
    let items: [Blog]?
}

/// Per-user access information for a blog (`blogger#blogUserInfo`).
struct BlogUserInfo: Codable {
    let kind: String?
    let blog: Blog?
    let blog_user_info: BlogPerUserInfo?

    struct BlogPerUserInfo: Codable {
        let kind: String?
        let userId: String?
        let blogId: String?
        let role: String?
        let hasAdminAccess: Bool?
        let hasAllAccess: Bool?
        let hasEditAccess: Bool?
        let hasImageAccess: Bool?
        let hasPageAccess: Bool?
        let hasPostAccess: Bool?
        let hasVideoAccess: Bool?
    }
}
