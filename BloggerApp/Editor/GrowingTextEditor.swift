import SwiftUI
import UIKit

/// A SwiftUI `TextEditor` that grows to fit content (no inner scroll), used
/// by plain-text blocks (code, list items, custom HTML).
struct GrowingTextEditor: UIViewRepresentable {
    @Binding var text: String
    var font: UIFont = .preferredFont(forTextStyle: .body)
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
        tv.text = text
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        guard (uiView.text ?? "") != text else { return }
        if !uiView.isFirstResponder {
            uiView.text = text
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: GrowingTextEditor
        init(_ parent: GrowingTextEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            let newText: String = textView.text ?? ""
            DispatchQueue.main.async {
                if self.parent.text != newText {
                    self.parent.text = newText
                }
            }
        }
    }
}