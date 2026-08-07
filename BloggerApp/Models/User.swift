import Foundation

/// The authenticated user (`blogger#user`).
struct BloggerUser: Codable {
    let kind: String?
    let id: String?
    let selfLink: String?
    let blogs: BlogsRef?

    struct BlogsRef: Codable {
        let selfLink: String?
    }
}
