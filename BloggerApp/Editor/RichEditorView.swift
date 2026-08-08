import SwiftUI
import UIKit
import WebKit

/// TipTap (ProseMirror) editor embedded in a WKWebView. The toolbar is a
/// fixed in-page row (tiptap "simple editor" style); HTML syncs through the
/// `html` binding via the JS bridge.
struct RichEditorView: View {
    @Binding var html: String
    let editorRef: RichEditorRef
    var onImageRequested: (() -> Void)?

    @State private var showLinkSheet = false
    @State private var linkText = ""
    @State private var linkURL = "https://"
    @State private var editorHeight: CGFloat = 320

    init(
        html: Binding<String>,
        editorRef: RichEditorRef,
        onImageRequested: (() -> Void)? = nil
    ) {
        _html = html
        self.editorRef = editorRef
        self.onImageRequested = onImageRequested
        editorRef.onImageRequested = onImageRequested
    }

    var body: some View {
        TipTapWebView(
            html: $html,
            editorRef: editorRef,
            height: $editorHeight,
            onLinkRequested: { showLinkSheet = true }
        )
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: max(320, editorHeight))
        .sheet(isPresented: $showLinkSheet) {
            linkSheet
        }
    }

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

/// Shared reference to the live editor for command execution.
final class RichEditorRef: ObservableObject {
    weak var coordinator: TipTapWebView.Coordinator?
    /// Wired by the host: opens the photo picker when the toolbar image
    /// button is tapped inside the page.
    var onImageRequested: (() -> Void)?

    func command(_ name: String) {
        coordinator?.run(script: "window.BloggerTipTap && window.BloggerTipTap.\(name)()")
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

/// WKWebView representable hosting the TipTap page. The webview's internal
/// scrolling is disabled; it reports its content height so SwiftUI sizes it to
/// fit inside the host's ScrollView (title + labels + editor scroll together).
struct TipTapWebView: UIViewRepresentable {
    @Binding var html: String
    let editorRef: RichEditorRef
    @Binding var height: CGFloat
    var onLinkRequested: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController = WKUserContentController()
        config.userContentController.add(context.coordinator, name: "editorState")
        config.userContentController.add(context.coordinator, name: "ready")
        config.userContentController.add(context.coordinator, name: "editorError")
        config.userContentController.add(context.coordinator, name: "editorFocus")
        config.userContentController.add(context.coordinator, name: "editorHeight")
        config.userContentController.add(context.coordinator, name: "insertImageRequested")
        config.userContentController.add(context.coordinator, name: "insertLinkRequested")

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 320), configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.keyboardDismissMode = .interactive
        // Let the host ScrollView own scrolling -> single scroll for the page.
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
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
            let htmlURL = bundleURL.appendingPathComponent("editor.html")
            guard FileManager.default.fileExists(atPath: htmlURL.path) else {
                print("[TipTap] editor.html missing at \(htmlURL.path)")
                return
            }
            webView.loadFileURL(htmlURL, allowingReadAccessTo: bundleURL)
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
            case "ready":
                hasLoaded = true
            case "editorError":
                print("[TipTap] JS error: \(message.body)")
            case "editorFocus":
                break
            case "editorHeight":
                if let h = message.body as? NSNumber {
                    let newHeight = CGFloat(h.doubleValue)
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        print("[TipTap] height reported: \(newHeight)")
                        guard abs(self.parent.height - newHeight) > 1 else { return }
                        self.parent.height = newHeight
                    }
                }
            case "insertImageRequested":
                print("[TipTap] image requested from editor")
                DispatchQueue.main.async { [weak self] in
                    self?.parent.editorRef.onImageRequested?()
                }
            case "insertLinkRequested":
                DispatchQueue.main.async { [weak self] in
                    self?.parent.onLinkRequested?()
                }
            default:
                break
            }
        }
    }
}
