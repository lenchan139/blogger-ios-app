import Foundation
import UIKit
import Combine

/// Tracks the text view that currently holds focus inside the block editor so
/// the format toolbar can apply changes to the right block. Mirrors the
/// "active editor" concept WordPress's Aztec toolbar uses, but per-block.
@MainActor
final class ActiveTextEditor: ObservableObject {
    static let shared = ActiveTextEditor()

    /// The focused text view (set by `HTMLTextView`/`GrowingTextEditor`
    /// coordinators when editing begins).
    weak var current: UITextView?

    /// Set to true when the focused editor should be considered a rich-text
    /// block (bold/italic/underline apply) rather than plain text.
    var isRichText = false

    /// Emitted after the toolbar mutates attributes so the owning block
    /// re-serializes HTML.
    var onDidApplyFormatting: (() -> Void)?
}

enum BlockEditorNotifications {
    /// Posted when an image upload starts; the block editor appends an
    /// "uploading" image block.
    static let imageUploadBegan = Notification.Name("blockEditor.imageUploadBegan")

    /// Posted when the upload finishes; the block editor fills in the URL.
    static let imageUploadFinished = Notification.Name("blockEditor.imageUploadFinished")

    static func postImageUploadFinished(url: String, caption: String, alt: String?) {
        var userInfo: [String: Any] = ["url": url, "caption": caption]
        if let alt { userInfo["alt"] = alt }
        NotificationCenter.default.post(name: imageUploadFinished, object: nil, userInfo: userInfo)
    }
}