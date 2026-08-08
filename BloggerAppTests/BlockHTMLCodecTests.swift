import XCTest
@testable import BloggerApp

final class BlockHTMLCodecTests: XCTestCase {

    func testDecodeSimpleParagraph() {
        let blocks = BlockHTMLCodec.decode("<p>Hello world</p>")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].type, .paragraph)
        XCTAssertEqual(blocks[0].content, "Hello world")
    }

    func testDecodeHeading() {
        let blocks = BlockHTMLCodec.decode("<h2>Section</h2>")
        XCTAssertEqual(blocks[0].type, .heading(level: 2))
        XCTAssertEqual(blocks[0].content, "Section")
    }

    func testDecodeList() {
        let blocks = BlockHTMLCodec.decode("<ul><li>One</li><li>Two</li></ul>")
        XCTAssertEqual(blocks[0].type, .list(ordered: false))
        XCTAssertEqual(blocks[0].content, "One\nTwo")
    }

    func testDecodeOrderedList() {
        let blocks = BlockHTMLCodec.decode("<ol><li>First</li></ol>")
        XCTAssertEqual(blocks[0].type, .list(ordered: true))
    }

    func testDecodeFigureImageWithCaption() {
        let html = "<figure><img src=\"https://x/y.jpg\" alt=\"cat\"/><figcaption>My cat</figcaption></figure>"
        let blocks = BlockHTMLCodec.decode(html)
        XCTAssertEqual(blocks[0].type, .image)
        XCTAssertEqual(blocks[0].content, "https://x/y.jpg")
        XCTAssertEqual(blocks[0].attributes["alt"], "cat")
        XCTAssertEqual(blocks[0].attributes["caption"], "My cat")
    }

    func testDecodeBareImage() {
        let blocks = BlockHTMLCodec.decode("<img src=\"https://x/a.png\" alt=\"pic\"/>")
        XCTAssertEqual(blocks[0].type, .image)
        XCTAssertEqual(blocks[0].attributes["caption"], nil)
    }

    func testDecodeDivider() {
        let blocks = BlockHTMLCodec.decode("<hr/>")
        XCTAssertEqual(blocks[0].type, .divider)
    }

    func testDecodeUnknownElementBecomesCustomHTML() {
        let html = "<table><tr><td>cell</td></tr></table>"
        let blocks = BlockHTMLCodec.decode(html)
        XCTAssertEqual(blocks[0].type, .customHTML)
        XCTAssertTrue(blocks[0].content.contains("<table>"))
    }

    func testDecodeInlineFormattingPreservedInParagraph() {
        let html = "<p>Hello <strong>bold</strong> and <a href=\"https://x\">link</a></p>"
        let blocks = BlockHTMLCodec.decode(html)
        XCTAssertEqual(blocks[0].type, .paragraph)
        XCTAssertTrue(blocks[0].content.contains("<strong>bold</strong>"))
        XCTAssertTrue(blocks[0].content.contains("<a href=\"https://x\">link</a>"))
    }

    func testDecodeEmptyReturnsParagraph() {
        let blocks = BlockHTMLCodec.decode("")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].type, .paragraph)
    }

    func testEncodeParagraph() {
        let blocks = [Block(type: .paragraph, content: "Hi")]
        XCTAssertEqual(BlockHTMLCodec.encode(blocks), "<p>Hi</p>")
    }

    func testEncodeHeading() {
        let blocks = [Block(type: .heading(level: 3), content: "T")]
        XCTAssertEqual(BlockHTMLCodec.encode(blocks), "<h3>T</h3>")
    }

    func testEncodeList() {
        let blocks = [Block(type: .list(ordered: false), content: "A\nB")]
        XCTAssertEqual(BlockHTMLCodec.encode(blocks), "<ul><li>A</li><li>B</li></ul>")
    }

    func testEncodeImageWithCaption() {
        let block = Block(type: .image, content: "https://x/z.jpg", attributes: ["alt": "a", "caption": "cap"])
        XCTAssertEqual(BlockHTMLCodec.encode([block]),
                       "<figure><img src=\"https://x/z.jpg\" alt=\"a\"/><figcaption>cap</figcaption></figure>")
    }

    func testRoundTripSimplePost() {
        let original = """
        <p>Intro paragraph</p>
        <h2>Header</h2>
        <p>Body with <strong>emphasis</strong>.</p>
        <ul><li>one</li><li>two</li></ul>
        <blockquote>A quote</blockquote>
        <hr/>
        """
        let blocks = BlockHTMLCodec.decode(original)
        let reencoded = BlockHTMLCodec.encode(blocks)
        let roundTripped = BlockHTMLCodec.decode(reencoded)

        XCTAssertEqual(blocks.count, 6)
        XCTAssertEqual(roundTripped.count, blocks.count)
        XCTAssertTrue(contentEqual(blocks, roundTripped), "Round-trip should preserve type/content/attributes")
    }

    /// Equality ignoring `id` (each decode mints fresh UUIDs).
    private func contentEqual(_ a: [Block], _ b: [Block]) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).allSatisfy { $0.type == $1.type && $0.content == $1.content && $0.attributes == $1.attributes }
    }
}
