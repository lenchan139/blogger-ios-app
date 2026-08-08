import Foundation
import SwiftSoup

/// Converts between the native `[Block]` model and Blogger's HTML `content`
/// string.
///
/// This mirrors the approach WordPress-iOS uses in
/// `Modules/Sources/GutenbergProcessors/GutenbergContentParser.swift`, except
/// that Blogger stores plain HTML (no Gutenberg `<!-- wp:... -->` markers), so
/// block boundaries must be *inferred* from the markup instead of read from
/// comments. Unknown markup is collapsed into a single `.customHTML` block so
/// nothing is lost on round-trip.
struct BlockHTMLCodec {

    // MARK: - Decode (HTML -> Blocks)

    /// Parses raw HTML into a list of blocks.
    static func decode(_ html: String) -> [Block] {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [.init(type: .paragraph)]
        }

        let doc = (try? SwiftSoup.parseBodyFragment(html)) ?? (try? SwiftSoup.parseBodyFragment(""))
        guard let body = doc?.body() else {
            return [.init(type: .customHTML, content: html)]
        }

        var blocks: [Block] = []
        for node in body.getChildNodes() {
            switch node {
            case let element as Element:
                blocks.append(block(for: element))
            case let textNode as TextNode:
                let text = textNode.getWholeText()
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.init(type: .paragraph, content: text))
                }
            default:
                break
            }
        }

        return blocks.isEmpty ? [.init(type: .paragraph)] : blocks
    }

    /// Maps a top-level element to a block, recursing into list items.
    private static func block(for element: Element) -> Block {
        let tag = element.tagName().lowercased()

        switch tag {
        case "p":
            return .init(type: .paragraph, content: (try? element.html()) ?? "")

        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(tag.dropFirst()) ?? 1
            return .init(type: .heading(level: level), content: (try? element.html()) ?? "")

        case "ul", "ol":
            let ordered = tag == "ol"
            let items = (try? element.select("li").array())?
                .compactMap { try? $0.html() } ?? []
            let content = items.joined(separator: "\n")
            return .init(type: .list(ordered: ordered), content: content)

        case "blockquote":
            return .init(type: .quote, content: (try? element.html()) ?? "")

        case "pre":
            return .init(type: .code, content: (try? element.html()) ?? "")

        case "hr":
            return .init(type: .divider)

        case "img":
            return imageBlock(from: element)

        case "figure":
            // `<figure><img .../><figcaption>...</figcaption></figure>`
            if let img = (try? element.select("img").first()) {
                var block = imageBlock(from: img)
                if let caption = (try? element.select("figcaption").first()?.html()) {
                    block.attributes["caption"] = caption
                }
                return block
            }
            return .init(type: .customHTML, content: (try? element.outerHtml()) ?? "")

        default:
            // Unknown element (div, table, script, embed, etc.) — keep raw.
            return .init(type: .customHTML, content: (try? element.outerHtml()) ?? "")
        }
    }

    private static func imageBlock(from element: Element) -> Block {
        let src = (try? element.attr("src")) ?? ""
        let alt = (try? element.attr("alt")) ?? ""
        var attributes: [String: String] = [:]
        if !alt.isEmpty { attributes["alt"] = alt }
        return .init(type: .image, content: src, attributes: attributes)
    }

    // MARK: - Encode (Blocks -> HTML)

    /// Serializes blocks back into Blogger-compatible HTML.
    static func encode(_ blocks: [Block]) -> String {
        blocks.compactMap { html(for: $0) }.joined(separator: "\n\n")
    }

    private static func html(for block: Block) -> String? {
        switch block.type {
        case .paragraph:
            return "<p>\(block.content)</p>"

        case .heading(let level):
            return "<h\(level)>\(block.content)</h\(level)>"

        case .list(let ordered):
            let tag = ordered ? "ol" : "ul"
            let items = block.content
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { "<li>\($0)</li>" }
                .joined()
            guard !items.isEmpty else { return "<\(tag)></\(tag)>" }
            return "<\(tag)>\(items)</\(tag)>"

        case .quote:
            return "<blockquote>\(block.content)</blockquote>"

        case .image:
            let src = block.content
            let alt = (block.attributes["alt"] ?? "").htmlAttributeEscaped
            if let caption = block.attributes["caption"], !caption.isEmpty {
                return "<figure><img src=\"\(src)\" alt=\"\(alt)\"/><figcaption>\(caption)</figcaption></figure>"
            }
            return "<img src=\"\(src)\" alt=\"\(alt)\"/>"

        case .code:
            return "<pre>\(block.content)</pre>"

        case .divider:
            return "<hr/>"

        case .customHTML:
            return block.content
        }
    }
}

private extension String {
    var htmlAttributeEscaped: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
