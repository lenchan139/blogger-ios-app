import SwiftUI
import UIKit

/// A UIViewRepresentable that renders and edits HTML content in a UITextView,
/// keeping the underlying HTML string in sync. Used as the post body editor.
struct RichTextEditor: UIViewRepresentable {
    @Binding var html: String
    var isEditable: Bool = true

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = isEditable
        textView.isScrollEnabled = true
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        // So we can detect changes from the HTML side.
        textView.text = Self.plainText(from: html)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let incomingPlain = Self.plainText(from: html)
        if uiView.text != incomingPlain {
            uiView.text = incomingPlain
        }
        uiView.isEditable = isEditable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private static func plainText(from html: String) -> String {
        guard let data = html.data(using: .unicode),
              let attributed = try? NSAttributedString(
                  data: data,
                  options: [.documentType: NSAttributedString.DocumentType.html,
                            .characterEncoding: String.Encoding.utf8.rawValue],
                  documentAttributes: nil
              ) else {
            return html
        }
        return attributed.string
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextEditor

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let html = Self.html(from: textView.text) else { return }
            parent.html = html
        }

        private static func html(from plainText: String) -> String? {
            let html = plainText
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\n", with: "<br>")
            return "<div>\(html)</div>"
        }
    }
}
