import SwiftUI
import UIKit
import WebKit

/// TipTap (ProseMirror) editor embedded in a WKWebView, styled and wired the
/// kMail way: HTML syncs through the `html` binding, and a SwiftUI toolbar is
/// pinned at the bottom via `.safeAreaInset` while the editor is focused.
struct RichEditorView: View {
    @Binding var html: String
    let editorRef: RichEditorRef
    var onImageRequested: (() -> Void)?

    @FocusState private var isEditorFocused: Bool
    @State private var showLinkSheet = false
    @State private var linkText = ""
    @State private var linkURL = "https://"
    @State private var state = EditorStateSnapshot()
    @State private var hasLoaded = false

    var body: some View {
        TipTapWebView(html: $html, editorRef: editorRef, onState: { snapshot in
            state = snapshot
            hasLoaded = true
        })
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 320)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isEditorFocused {
                toolbar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showLinkSheet) {
            linkSheet
        }
    }

    // MARK: - Toolbar (kMail-style bottom bar)

    private var toolbar: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    toolbarButton("arrow.uturn.backward") { editorRef.command("undo") }
                    toolbarButton("arrow.uturn.forward") { editorRef.command("redo") }

                    Divider().frame(height: 22)

                    toolbarButton("bold", isActivated: state.bold) { editorRef.command("bold") }
                    toolbarButton("italic", isActivated: state.italic) { editorRef.command("italic") }
                    toolbarButton("underline", isActivated: state.underline) { editorRef.command("underline") }
                    toolbarButton("strikethrough", isActivated: state.strike) { editorRef.command("strike") }

                    Divider().frame(height: 22)

                    toolbarButton("list.bullet", isActivated: state.bulletList) { editorRef.command("bulletList") }
                    toolbarButton("list.number", isActivated: state.orderedList) { editorRef.command("orderedList") }
                    toolbarButton("quote.opening", isActivated: state.blockquote) { editorRef.command("blockquote") }
                    toolbarButton("minus") { editorRef.command("insertHorizontalRule") }

                    Divider().frame(height: 22)

                    toolbarButton("text.alignleft", isActivated: state.alignLeft) { editorRef.command("alignLeft") }
                    toolbarButton("text.aligncenter", isActivated: state.alignCenter) { editorRef.command("alignCenter") }
                    toolbarButton("text.alignright", isActivated: state.alignRight) { editorRef.command("alignRight") }

                    Divider().frame(height: 22)

                    toolbarButton("link", isActivated: state.hasLink) {
                        if state.hasLink {
                            editorRef.command("unlink")
                        } else {
                            linkText = ""
                            linkURL = "https://"
                            showLinkSheet = true
                        }
                    }
                    if onImageRequested != nil {
                        toolbarButton("photo.on.rectangle.angled") { onImageRequested?() }
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
        .animation(.default.speed(2), value: isEditorFocused)
    }

    private func toolbarButton(
        _ systemName: String,
        isActivated: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .regular))
                .frame(width: 38, height: 38)
                .background(isActivated ? Color.accentColor : Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(isActivated ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Link sheet

    private var linkSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Link text", text: $linkText)
                    TextField("URL", text: $linkURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Add link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showLinkSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let url = URL(string: linkURL) {
                            editorRef.setLink(url: url.absoluteString)
                        }
                        showLinkSheet = false
                    }
                    .bold()
                }
            }
        }
    }
}

/// Selection state reported from the editor on every transaction.
struct EditorStateSnapshot: Equatable {
    var bold = false
    var italic = false
    var underline = false
    var strike = false
    var bulletList = false
    var orderedList = false
    var blockquote = false
    var alignLeft = false
    var alignCenter = false
    var alignRight = false
    var hasLink = false

    init(dict: [String: Any]? = nil) {
        guard let dict else { return }
        bold = dict["bold"] as? Bool ?? false
        italic = dict["italic"] as? Bool ?? false
        underline = dict["underline"] as? Bool ?? false
        strike = dict["strike"] as? Bool ?? false
        bulletList = dict["bulletList"] as? Bool ?? false
        orderedList = dict["orderedList"] as? Bool ?? false
        blockquote = dict["blockquote"] as? Bool ?? false
        alignLeft = dict["alignLeft"] as? Bool ?? false
        alignCenter = dict["alignCenter"] as? Bool ?? false
        alignRight = dict["alignRight"] as? Bool ?? false
        hasLink = dict["hasLink"] as? Bool ?? false
    }
}

/// Shared reference to the live editor for command execution.
final class RichEditorRef: ObservableObject {
    weak var coordinator: TipTapWebView.Coordinator?

    func command(_ name: String) {
        coordinator?.run(command: name)
    }

    func setLink(url: String) {
        coordinator?.run(script: "window.BloggerTipTap && window.BloggerTipTap.setLink(\(url.jsEscaped))")
    }

    func insertImage(url: String, caption: String) {
        coordinator?.run(script: "window.BloggerTipTap && window.BloggerTipTap.insertImage(\(url.jsEscaped), \(caption.jsEscaped))")
    }
}

private extension String {
    var jsEscaped: String {
        let escaped = replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}

/// WKWebView representable hosting the TipTap page.
struct TipTapWebView: UIViewRepresentable {
    @Binding var html: String
    let editorRef: RichEditorRef
    var onState: (EditorStateSnapshot) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController = WKUserContentController()
        config.userContentController.add(context.coordinator, name: "editorState")
        config.userContentController.add(context.coordinator, name: "ready")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.keyboardDismissMode = .interactive
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        editorRef.coordinator = context.coordinator
        context.coordinator.loadPage()
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
        editorRef.coordinator = context.coordinator
        if html != context.coordinator.lastReported {
            context.coordinator.setHTML(html)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: TipTapWebView
        weak var webView: WKWebView?
        private var hasLoaded = false
        var lastReported = ""

        init(_ parent: TipTapWebView) { self.parent = parent }

        func loadPage() {
            guard let webView, let bundleURL = Bundle.main.resourceURL else { return }
            let editorDir = bundleURL.appendingPathComponent("Editor", isDirectory: true)
            let htmlURL = editorDir.appendingPathComponent("editor.html")
            guard FileManager.default.fileExists(atPath: htmlURL.path) else {
                print("[TipTap] editor.html missing at \(htmlURL.path)")
                return
            }
            webView.loadFileURL(htmlURL, allowingReadAccessTo: editorDir)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            hasLoaded = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.setHTML(self?.parent.html ?? "")
            }
        }

        func setHTML(_ html: String) {
            guard hasLoaded else { return }
            run(script: "window.BloggerTipTap && window.BloggerTipTap.setHTML(\(html.jsEscaped))")
        }

        func run(command: String) {
            run(script: "window.BloggerTipTap && window.BloggerTipTap.\(command)()")
        }

        func run(script: String) {
            webView?.evaluateJavaScript(script) { _, error in
                if let error { print("[TipTap] JS error: \(error.localizedDescription)") }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "editorState":
                guard let dict = message.body as? [String: Any] else { return }
                let html = dict["html"] as? String ?? ""
                if html != lastReported {
                    lastReported = html
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.parent.html != html else { return }
                        self.parent.html = html
                    }
                }
                DispatchQueue.main.async { [weak self] in
                    self?.parent.onState(EditorStateSnapshot(dict: dict))
                }
            case "ready":
                hasLoaded = true
            default:
                break
            }
        }
    }
}
