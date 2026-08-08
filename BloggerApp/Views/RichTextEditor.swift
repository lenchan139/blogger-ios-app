import SwiftUI
import UIKit
import Aztec

/// A rich HTML editor backed by Aztec (the editor the WordPress app ships with).
/// It is a native `UITextView` subclass, so formatting applies directly to the
/// text (no webview / execCommand focus issues), and it renders images natively.
/// Tables render as an "HTML" block; use the HTML source toggle to edit them.
struct RichTextEditor: View {
    @Binding var html: String
    @StateObject private var editorRef: EditorRef
    @StateObject private var router: EditorRouter
    private let accessoryView: UIView

    init(html: Binding<String>) {
        _html = html
        let editorRef = EditorRef()
        let router = EditorRouter()
        _editorRef = StateObject(wrappedValue: editorRef)
        _router = StateObject(wrappedValue: router)

        let toolbar = AztecFormattingToolbar(editorRef: editorRef, router: router)
        toolbar.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44)
        accessoryView = toolbar
    }

    var body: some View {
        AztecTextView(html: $html, editorRef: editorRef, accessoryView: accessoryView)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { editorRef.onHTMLChange = { html = $0 } }
            .sheet(isPresented: $router.showLinkSheet) {
                LinkInputView(editorRef: editorRef, router: router)
            }
    }
}

/// Shared, stable reference to the underlying editor so the toolbar can apply
/// formatting directly and sync the HTML binding.
final class EditorRef: ObservableObject {
    weak var view: Aztec.TextView?
    var onHTMLChange: ((String) -> Void)?

    func apply(_ command: (Aztec.TextView) -> Void) {
        guard let textView = view else { return }
        command(textView)
        onHTMLChange?(textView.getHTML())
    }
}

/// Shared state between the editor and its accessory toolbar.
final class EditorRouter: ObservableObject {
    @Published var showLinkSheet = false
}

// MARK: - Aztec TextView wrapper

private struct AztecTextView: UIViewRepresentable {
    @Binding var html: String
    var editorRef: EditorRef
    var accessoryView: UIView

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> Aztec.TextView {
        let textView = Aztec.TextView(
            defaultFont: .preferredFont(forTextStyle: .body),
            defaultParagraphStyle: .default,
            defaultMissingImage: UIImage(systemName: "photo")!
        )
        textView.isEditable = true
        textView.isScrollEnabled = false
        textView.alwaysBounceVertical = false
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.textAttachmentDelegate = context.coordinator
        textView.registerAttachmentImageProvider(DefaultAttachmentImageProvider())
        textView.inputAccessoryView = accessoryView
        // Avoid the attachment-layout crash from a zero-width initial frame.
        textView.frame = CGRect(x: 0, y: 0, width: max(UIScreen.main.bounds.width, 300), height: 400)

        editorRef.view = textView
        context.coordinator.setHTMLIfReady(html, in: textView)
        return textView
    }

    func updateUIView(_ uiView: Aztec.TextView, context: Context) {
        context.coordinator.parent = self
        uiView.inputAccessoryView = accessoryView
        context.coordinator.setHTMLIfReady(html, in: uiView)
    }

    final class Coordinator: NSObject, UITextViewDelegate, TextViewAttachmentDelegate {
        var parent: AztecTextView

        init(_ parent: AztecTextView) {
            self.parent = parent
        }

        func setHTMLIfReady(_ html: String, in textView: Aztec.TextView) {
            guard textView.bounds.width > 0 else { return }
            guard textView.getHTML() != html else { return }
            textView.setHTML(html)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let aztec = textView as? Aztec.TextView else { return }
            let newHTML = aztec.getHTML()
            if newHTML != parent.html {
                parent.html = newHTML
            }
        }

        // MARK: - TextViewAttachmentDelegate (remote image loading)

        func textView(
            _ textView: TextView,
            attachment: NSTextAttachment,
            imageAt url: URL,
            onSuccess success: @escaping (UIImage) -> Void,
            onFailure failure: @escaping () -> Void
        ) {
            URLSession.shared.dataTask(with: url) { data, _, error in
                guard error == nil, let data, let image = UIImage(data: data) else {
                    DispatchQueue.main.async { failure() }
                    return
                }
                DispatchQueue.main.async { success(image) }
            }.resume()
        }

        func textView(_ textView: TextView, urlFor imageAttachment: ImageAttachment) -> URL? {
            imageAttachment.url
        }

        func textView(_ textView: TextView, placeholderFor attachment: NSTextAttachment) -> UIImage {
            UIImage(systemName: "photo") ?? UIImage()
        }

        func textView(_ textView: TextView, deletedAttachment attachment: MediaAttachment) {}
        func textView(_ textView: TextView, selected attachment: NSTextAttachment, atPosition position: CGPoint) {}
        func textView(_ textView: TextView, deselected attachment: NSTextAttachment, atPosition position: CGPoint) {}
    }
}

/// Supplies a valid size and placeholder image for Aztec attachments, which
/// Aztec requires or it crashes / hits a fatalError.
private final class DefaultAttachmentImageProvider: TextViewAttachmentImageProvider {
    func textView(_ textView: TextView, shouldRender attachment: NSTextAttachment) -> Bool {
        !(attachment is MediaAttachment)
    }

    func textView(_ textView: TextView, boundsFor attachment: NSTextAttachment, with lineFragment: CGRect) -> CGRect {
        CGRect(x: 0, y: 0, width: max(lineFragment.width, 1), height: 220)
    }

    func textView(_ textView: TextView, imageFor attachment: NSTextAttachment, with size: CGSize) -> UIImage? {
        UIImage(systemName: "photo")
    }
}

// MARK: - Formatting toolbar

private final class AztecFormattingToolbar: UIView {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let editorRef: EditorRef
    private let router: EditorRouter

    init(editorRef: EditorRef, router: EditorRouter) {
        self.editorRef = editorRef
        self.router = router
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.isDirectionalLockEnabled = true
        addSubview(scrollView)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .center
        stackView.layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        stackView.isLayoutMarginsRelativeArrangement = true
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            scrollView.frameLayoutGuide.heightAnchor.constraint(equalTo: stackView.heightAnchor)
        ])

        addButton("arrow.uturn.backward", #selector(undoTapped))
        addButton("arrow.uturn.forward", #selector(redoTapped))
        addButton("bold", #selector(boldTapped))
        addButton("italic", #selector(italicTapped))
        addButton("underline", #selector(underlineTapped))
        addButton("strikethrough", #selector(strikeTapped))
        addButton("list.bullet", #selector(bulletTapped))
        addButton("list.number", #selector(numberTapped))
        addButton("textformat.header", #selector(headerTapped))
        addButton("quote.opening", #selector(quoteTapped))
        addButton("link", #selector(linkTapped))
    }

    private func addButton(_ symbol: String, _ action: Selector) {
        let button = UIButton(configuration: .borderless())
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.tintColor = .tintColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: action, for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 40).isActive = true
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        stackView.addArrangedSubview(button)
    }

    private var selectedRange: NSRange {
        editorRef.view?.selectedRange ?? NSRange(location: 0, length: 0)
    }

    @objc private func undoTapped() { editorRef.view?.undoManager?.undo() }
    @objc private func redoTapped() { editorRef.view?.undoManager?.redo() }
    @objc private func boldTapped() { editorRef.apply { $0.toggleBold(range: self.selectedRange) } }
    @objc private func italicTapped() { editorRef.apply { $0.toggleItalic(range: self.selectedRange) } }
    @objc private func underlineTapped() { editorRef.apply { $0.toggleUnderline(range: self.selectedRange) } }
    @objc private func strikeTapped() { editorRef.apply { $0.toggleStrikethrough(range: self.selectedRange) } }
    @objc private func bulletTapped() { editorRef.apply { $0.toggleUnorderedList(range: self.selectedRange) } }
    @objc private func numberTapped() { editorRef.apply { $0.toggleOrderedList(range: self.selectedRange) } }
    @objc private func headerTapped() { editorRef.apply { $0.toggleHeader(.h1, range: self.selectedRange) } }
    @objc private func quoteTapped() { editorRef.apply { $0.toggleBlockquote(range: self.selectedRange) } }
    @objc private func linkTapped() { router.showLinkSheet = true }
}

// MARK: - Link input

private struct LinkInputView: View {
    let editorRef: EditorRef
    let router: EditorRouter
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var url = "https://"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Link text", text: $text)
                    TextField("URL", text: $url)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Add link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let linkURL = URL(string: url) {
                            editorRef.view?.setLink(linkURL, title: text.isEmpty ? url : text, inRange: editorRef.view?.selectedRange ?? NSRange())
                            editorRef.onHTMLChange?(editorRef.view?.getHTML() ?? "")
                        }
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}
