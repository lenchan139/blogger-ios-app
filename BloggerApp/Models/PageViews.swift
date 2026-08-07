import Foundation

/// Blog pageview statistics (`blogger#pageviews`).
struct PageViews: Codable {
    let kind: String?
    let blogId: String?
    let counts: [Count]?

    struct Count: Codable {
        let timeRange: String?
        let timeRangeString: String?
        let views: Int?
    }
}
