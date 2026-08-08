import SwiftUI
import WebKit

/// Quill.js rich text editor embedded in a WKWebView. Content flows in/out as
/// an HTML string, matching the Blogger API's `content` field and the host's
/// `htmlBody` binding.
///
/// HTML direction:
///  - Native -> JS: `setData(html)` (on load, external changes, source toggle)
///  - JS -> Native: `editorContent` message on every `change:data` event
///
/// A `suppressDataEvents` guard in the host page prevents feedback loops while
/// setData is applied.
struct CKEditorView: UIViewRepresentable {
    @Binding var html: String
    /// Shared reference; the view registers its live coordinator on it so the
    /// host can insert images etc.
    let editorRef: CKEditorRef

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController = WKUserContentController()
        config.userContentController.add(context.coordinator, name: "editorContent")
        config.userContentController.add(context.coordinator, name: "editorReady")
        config.userContentController.add(context.coordinator, name: "editorError")
        config.userContentController.add(context.coordinator, name: "insertImageRequested")
        config.userContentController.add(context.coordinator, name: "insertVideoRequested")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.keyboardDismissMode = .interactive
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        editorRef.coordinator = context.coordinator
        context.coordinator.loadEditor()
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
        // Keep ref wiring in sync (host callbacks may be set after makeUIView).
        editorRef.coordinator = context.coordinator
        // External edits (e.g. the HTML source toggle) must flow back into
        // the editor; skip when the editor itself produced the change.
        if html != context.coordinator.lastReported {
            context.coordinator.setData(html)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: CKEditorView
        weak var webView: WKWebView?
        private var hasLoaded = false
        var lastReported = ""

        init(_ parent: CKEditorView) { self.parent = parent }

        // MARK: - Loading

        func loadEditor() {
            guard let webView, let bundleURL = Bundle.main.resourceURL else { return }
            let htmlURL = bundleURL.appendingPathComponent("editor.html")
            guard FileManager.default.fileExists(atPath: htmlURL.path) else {
                print("[CKEditor] editor.html missing at \(htmlURL.path)")
                return
            }
            webView.loadFileURL(htmlURL, allowingReadAccessTo: bundleURL)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            hasLoaded = true
            // Push initial content once the page (and CKEditor) is up.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.setData(self?.parent.html ?? "")
            }
        }

        // MARK: - HTML sync

        func setData(_ html: String) {
            guard hasLoaded else { return }
            let escaped = html
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            webView?.evaluateJavaScript("window.QuillBridge && window.QuillBridge.setHTML(\"\(escaped)\")") { _, error in
                if let error { print("[Editor] setHTML error: \(error.localizedDescription)") }
            }
        }

        func insertImage(url: String, caption: String, alt: String?) {
            let captionEscaped = caption
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let js = """
            window.QuillBridge && window.QuillBridge.insertImage("\(url)", "\(captionEscaped)")
            """
            webView?.evaluateJavaScript(js) { _, error in
                if let error { print("[Editor] insertImage error: \(error.localizedDescription)") }
            }
        }

        func insertVideo(url: String) {
            let urlEscaped = url.replacingOccurrences(of: "\\", with: "\\\\")
            webView?.evaluateJavaScript("window.QuillBridge && window.QuillBridge.insertVideo(\"\(urlEscaped)\")") { _, error in
                if let error { print("[Editor] insertVideo error: \(error.localizedDescription)") }
            }
        }

        // MARK: - JS -> Native

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "editorContent":
                guard let html = message.body as? String else { return }
                if html != lastReported {
                    lastReported = html
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.parent.html != html else { return }
                        self.parent.html = html
                    }
                }
            case "insertImageRequested":
                onInsertImageRequested?()
            case "insertVideoRequested":
                onInsertVideoRequested?()
            case "editorReady":
                break
            case "editorError":
                print("[Editor] JS error: \(message.body)")
            default:
                break
            }
        }

        /// Called when the user taps the image button inside the editor.
        var onInsertImageRequested: (() -> Void)?
        /// Called when the user taps the video button inside the editor.
        var onInsertVideoRequested: (() -> Void)?
    }
}

/// Shared reference so the host view can reach into the live editor
/// (e.g. to insert a just-uploaded image).
final class CKEditorRef: ObservableObject {
    /// Callback wired by the host: opens the photo picker / camera.
    var onInsertImageRequested: (() -> Void)?
    /// Callback wired by the host: prompts for a video URL.
    var onInsertVideoRequested: (() -> Void)?

    var coordinator: CKEditorView.Coordinator? {
        didSet {
            coordinator?.onInsertImageRequested = onInsertImageRequested
            coordinator?.onInsertVideoRequested = onInsertVideoRequested
        }
    }

    func insertImage(url: String, caption: String, alt: String?) {
        coordinator?.insertImage(url: url, caption: caption, alt: alt)
    }

    func insertVideo(url: String) {
        coordinator?.insertVideo(url: url)
    }
}