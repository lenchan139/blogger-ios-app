import Foundation

/// The set of block kinds the editor understands. Unknown / arbitrary HTML is
/// represented by `.customHTML` so it round-trips losslessly.
enum BlockType: Equatable {
    case paragraph
    case heading(level: Int)
    case list(ordered: Bool)
    case quote
    case image
    case code
    case divider
    case customHTML

    static func == (lhs: BlockType, rhs: BlockType) -> Bool {
        switch (lhs, rhs) {
        case (.paragraph, .paragraph): return true
        case (.heading(let a), .heading(let b)): return a == b
        case (.list(let a), .list(let b)): return a == b
        case (.quote, .quote): return true
        case (.image, .image): return true
        case (.code, .code): return true
        case (.divider, .divider): return true
        case (.customHTML, .customHTML): return true
        default: return false
        }
    }

    var isTextBlock: Bool {
        switch self {
        case .paragraph, .heading, .list, .quote, .code: return true
        default: return false
        }
    }
}

/// A discrete, movable unit of post content. Stored as an HTML string at the
/// API boundary; `BlockHTMLCodec` converts between this model and raw HTML.
struct Block: Identifiable, Equatable {
    let id: UUID
    var type: BlockType

    /// Inline HTML for text blocks (e.g. `Hello <strong>world</strong>`).
    /// For `.image` this holds the remote source URL.
    var content: String

    /// Block-type-specific metadata (image alt text / caption, etc.).
    var attributes: [String: String]

    init(
        id: UUID = UUID(),
        type: BlockType,
        content: String = "",
        attributes: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.attributes = attributes
    }
}
