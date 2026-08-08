import Foundation
import UIKit

/// Applies inline formatting to the selected range of the active block text
/// view, then re-serializes HTML through the owning block.
@MainActor
enum RichTextFormatting {

    static var currentTextView: UITextView? {
        ActiveTextEditor.shared.current
    }

    // MARK: - Toggles

    static func toggleBold() {
        applyFontTrait(.traitBold)
    }

    static func toggleItalic() {
        applyFontTrait(.traitItalic)
    }

    static func toggleUnderline() {
        guard let tv = currentTextView, let attributed = tv.attributedText else { return }
        let range = tv.selectedRange
        guard range.length > 0 else { return }

        let isUnderlined = (attributed.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue
        let newValue: Any = isUnderlined ? 0 : NSUnderlineStyle.single.rawValue
        let attributes: [NSAttributedString.Key: Any] = [.underlineStyle: newValue]

        let copy = NSMutableAttributedString(attributedString: attributed)
        copy.addAttributes(attributes, range: range)
        tv.attributedText = copy
        tv.selectedRange = range
        notifyFormattingChanged()
    }

    static func toggleStrikethrough() {
        guard let tv = currentTextView, let attributed = tv.attributedText else { return }
        let range = tv.selectedRange
        guard range.length > 0 else { return }

        let isStruck = (attributed.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue
        let newValue: Any = isStruck ? 0 : NSUnderlineStyle.single.rawValue
        let attributes: [NSAttributedString.Key: Any] = [.strikethroughStyle: newValue]

        let copy = NSMutableAttributedString(attributedString: attributed)
        copy.addAttributes(attributes, range: range)
        tv.attributedText = copy
        tv.selectedRange = range
        notifyFormattingChanged()
    }

    static func addLink(_ url: URL, title: String) {
        guard let tv = currentTextView, let attributed = tv.attributedText else { return }
        var range = tv.selectedRange
        if range.length == 0 {
            range = NSRange(location: attributed.length, length: 0)
            tv.selectedRange = range
        }

        let copy = NSMutableAttributedString(attributedString: attributed)
        copy.addAttribute(.link, value: url, range: range)
        copy.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        tv.attributedText = copy
        tv.selectedRange = range
        notifyFormattingChanged()
    }

    // MARK: - Helpers

    private static func applyFontTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let tv = currentTextView, let attributed = tv.attributedText else { return }
        let range = tv.selectedRange
        guard range.length > 0 else { return }

        let copy = NSMutableAttributedString(attributedString: attributed)
        let baseFont = attributed.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont ?? tv.font ?? .preferredFont(forTextStyle: .body)

        // Apply to each glyph run so partially-bold selections toggle correctly.
        var searchRange = range
        while searchRange.length > 0 {
            var effective = NSRange(location: 0, length: 0)
            let runFont = copy.attribute(.font, at: searchRange.location, longestEffectiveRange: &effective, in: searchRange)
            guard effective.length > 0 else { break }
            let font = runFont as? UIFont ?? baseFont
            let traits = font.fontDescriptor.symbolicTraits
            let hasTrait = traits.contains(trait)
            var newTraits = traits
            if hasTrait {
                newTraits.remove(trait)
            } else {
                newTraits.insert(trait)
            }
            if let descriptor = font.fontDescriptor.withSymbolicTraits(newTraits) {
                copy.addAttribute(.font, value: UIFont(descriptor: descriptor, size: font.pointSize), range: effective)
            }
            searchRange.location = effective.location + effective.length
            searchRange.length = range.location + range.length - searchRange.location
        }

        tv.attributedText = copy
        tv.selectedRange = range
        notifyFormattingChanged()
    }

    private static func notifyFormattingChanged() {
        ActiveTextEditor.shared.onDidApplyFormatting?()
    }
}