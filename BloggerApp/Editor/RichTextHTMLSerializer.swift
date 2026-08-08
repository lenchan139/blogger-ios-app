import Foundation
import UIKit

/// Lightweight bidirectional converter between an HTML fragment (inline only —
/// `<strong>`, `<em>`, `<u>`, `<a>`, `<br>`) and `NSAttributedString`. Kept
/// deliberately small: block-level structure is owned by `BlockHTMLCodec`, so
/// text blocks only need inline rich text.
enum RichTextHTMLSerializer {

    // MARK: - HTML -> NSAttributedString

    static func attributed(from html: String, font: UIFont) -> NSAttributedString {
        let clean = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return NSAttributedString() }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]

        if let data = clean.data(using: .utf8),
           let attr = try? NSMutableAttributedString(
               data: data,
               options: options,
               documentAttributes: nil
           ) {
            attr.enumerateAttribute(.font, in: NSRange(location: 0, length: attr.length), options: []) { value, range, _ in
                guard let current = value as? UIFont else { return }
                // Re-baseline block default font while preserving symbolic traits
                // (bold/italic) that the HTML parser applied.
                let traits = current.fontDescriptor.symbolicTraits
                let descriptor = font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor
                attr.addAttribute(.font, value: UIFont(descriptor: descriptor, size: font.pointSize), range: range)
            }
            // Normalize trailing newline that the HTML importer appends.
            if attr.string.hasSuffix("\n") {
                attr.deleteCharacters(in: NSRange(location: attr.length - 1, length: 1))
            }
            return attr
        }

        // Fallback: treat as plain escaped text.
        return NSAttributedString(string: clean.rtHtmlUnescaped, attributes: [.font: font])
    }

    // MARK: - NSAttributedString -> HTML

    static func html(from attributed: NSAttributedString) -> NSAttributedString {
        attributed
    }

    static func htmlString(from attributed: NSAttributedString) -> String {
        guard attributed.length > 0 else { return "" }

        var output = ""
        var i = 0
        let full = NSRange(location: 0, length: attributed.length)

        // Track attributes open across runs.
        var bold = false, italic = false, underline = false
        var link: String?

        attributed.enumerateAttributes(in: full, options: []) { attrs, range, _ in
            let isBold = (attrs[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) == true
            let isItalic = (attrs[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true
            let isUnderline = (attrs[.underlineStyle] as? Int ?? 0) != 0
            let activeLink = attrs[.link] as? URL

            closeAndOpen(&output, bold: &bold, italic: &italic, underline: &underline, link: &link,
                         newBold: isBold, newItalic: isItalic, newUnderline: isUnderline, newLink: activeLink?.absoluteString)

            let substring = attributed.attributedSubstring(from: range).string
            output += substring.rtHtmlEscaped
            _ = i
        }

        // Close any still-open tags.
        closeAll(&output, bold: &bold, italic: &italic, underline: &underline, link: &link)

        return output
    }

    private static func closeAndOpen(_ out: inout String,
                                     bold: inout Bool, italic: inout Bool, underline: inout Bool, link: inout String?,
                                     newBold: Bool, newItalic: Bool, newUnderline: Bool, newLink: String?) {
        // Reopen everything when any inline state changes (simplest, safe).
        let changed = newBold != bold || newItalic != italic || newUnderline != underline || newLink != link
        guard changed else { return }
        closeAll(&out, bold: &bold, italic: &italic, underline: &underline, link: &link)
        bold = newBold; italic = newItalic; underline = newUnderline; link = newLink
        openAll(&out, bold: bold, italic: italic, underline: underline, link: link)
    }

    private static func closeAll(_ out: inout String, bold: inout Bool, italic: inout Bool, underline: inout Bool, link: inout String?) {
        if underline { out += "</u>"; underline = false }
        if link != nil { out += "</a>"; link = nil }
        if italic { out += "</em>"; italic = false }
        if bold { out += "</strong>"; bold = false }
    }

    private static func openAll(_ out: inout String, bold: Bool, italic: Bool, underline: Bool, link: String?) {
        if bold { out += "<strong>" }
        if italic { out += "<em>" }
        if let link { out += "<a href=\"\(link.rtHtmlAttributeEscaped)\">" }
        if underline { out += "<u>" }
    }
}

private extension String {
    var rtHtmlEscaped: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    var rtHtmlUnescaped: String {
        self.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    var rtHtmlAttributeEscaped: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}