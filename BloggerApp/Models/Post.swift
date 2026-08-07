import Foundation

/// A blog post (`blogger#post`).
struct Post: Codable, Identifiable {
    let kind: String
    let id: String
    let blog: BlogRef?
    let published: String?
    let updated: String?
    let url: String?
    let selfLink: String?
    var title: String?
    var content: String?
    var author: Author?
    var replies: CountInfo?
    let status: PostStatus?
    var labels: [String]?
    let location: Location?

    struct BlogRef: Codable {
        let id: String?
    }

    struct Author: Codable {
        let id: String?
        let displayName: String?
        let url: String?
        let image: ImageInfo?
    }

    struct ImageInfo: Codable {
        let url: String?
    }

    struct CountInfo: Codable {
        let totalItems: FlexibleInt?
        let selfLink: String?
    }

    struct Location: Codable {
        let name: String?
        let lat: Double?
        let lng: Double?
        let span: String?
    }

    /// Raw enum matching Blogger's `status` values. Blogger returns these in
    /// uppercase (e.g. "DRAFT"), so decoding is case-insensitive.
    enum PostStatus: String, Codable {
        case live
        case draft
        case scheduled
        case error

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let status = PostStatus(rawValue: raw.lowercased()) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown post status: \(raw)"
                )
            }
            self = status
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue.uppercased())
        }
    }
}

/// Wrapper for the posts list endpoint (paginated).
struct PostList: Codable {
    let kind: String?
    let items: [Post]?
    let nextPageToken: String?
    let prevPageToken: String?
    let etag: String?
}
