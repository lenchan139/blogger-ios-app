import Foundation

/// A static page (`blogger#page`).
struct Page: Codable, Identifiable {
    let kind: String
    let id: String
    let blog: BlogRef?
    let published: String?
    let updated: String?
    let url: String?
    let selfLink: String?
    let title: String?
    let content: String?
    let author: Post.Author?

    struct BlogRef: Codable {
        let id: String?
    }
}

/// Wrapper for the pages list endpoint.
struct PageList: Codable {
    let kind: String?
    let items: [Page]?
    let nextPageToken: String?
}

/// A comment on a post (`blogger#comment`).
struct Comment: Codable, Identifiable {
    let kind: String
    let id: String
    let post: PostRef?
    let blog: BlogRef?
    let published: String?
    let updated: String?
    let selfLink: String?
    let content: String?
    let author: Post.Author?
    let status: CommentStatus?
    let inReplyTo: ReplyRef?

    struct PostRef: Codable {
        let id: String?
    }

    struct BlogRef: Codable {
        let id: String?
    }

    struct ReplyRef: Codable {
        let id: String?
    }

    enum CommentStatus: String, Codable {
        case live
        case spam
        case pending
        case awaitingModeration
    }
}

/// Wrapper for the comments list endpoint.
struct CommentList: Codable {
    let kind: String?
    let items: [Comment]?
    let nextPageToken: String?
    let prevPageToken: String?
}
