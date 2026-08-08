import SwiftUI
import UIKit

/// A growable UITextView that edits inline rich text and serializes back to
/// HTML. Used by paragraph/heading/quote blocks so bold/italic/links render
/// inline (matching Gutenberg's inline rich-text), but scoped to one block.
struct HTMLTextView: UIViewRepresentable {
    @Binding var html: String
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var placeholder: String = ""
    var minHeight: CGFloat = 36

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.alwaysBounceVertical = false
        tv.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.font = font
        tv.delegate = context.coordinator
        tv.adjustsFontForContentSizeCategory = true
        tv.frame = CGRect(x: 0, y: 0, width: 300, height: minHeight)
        context.coordinator.load(html, into: tv)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        guard !uiView.isFirstResponder else { return }
        let current = RichTextHTMLSerializer.htmlString(from: uiView.attributedText)
        if current != html {
            context.coordinator.load(html, into: uiView)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: HTMLTextView
        private var lastEmitted: String

        init(_ parent: HTMLTextView) {
            self.parent = parent
            self.lastEmitted = parent.html
        }

        func load(_ html: String, into tv: UITextView) {
            let attr = RichTextHTMLSerializer.attributed(from: html, font: parent.font)
            tv.attributedText = attr
            if attr.length == 0, !parent.placeholder.isEmpty {
                tv.text = parent.placeholder
                tv.textColor = .placeholderText
            } else {
                tv.textColor = .label
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if textView.textColor == .placeholderText {
                textView.text = ""
                textView.textColor = .label
            }
            ActiveTextEditor.shared.current = textView
            ActiveTextEditor.shared.isRichText = true
            ActiveTextEditor.shared.onDidApplyFormatting = { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.syncHTML(from: textView)
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if ActiveTextEditor.shared.current === textView {
                ActiveTextEditor.shared.current = nil
                ActiveTextEditor.shared.onDidApplyFormatting = nil
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            syncHTML(from: textView)
        }

        private func syncHTML(from textView: UITextView) {
            let newHTML = RichTextHTMLSerializer.htmlString(from: textView.attributedText)
            guard newHTML != lastEmitted else { return }
            lastEmitted = newHTML
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.parent.html != newHTML {
                    self.parent.html = newHTML
                }
            }
        }
    }
}