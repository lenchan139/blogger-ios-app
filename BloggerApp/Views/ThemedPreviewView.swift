import SwiftUI
import WebKit

/// Renders post HTML styled with the blog's live theme, so previews match the
/// actual published look.
struct ThemedPreviewView: View {
    let blog: Blog
    let html: String
    @Environment(\.dismiss) private var dismiss

    @State private var themeCSS = ""
    @State private var isLoading = true
    @State private var themeLoaded = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading preview…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ThemedWebView(html: themedHTML)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(blog.name ?? "Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        themeLoaded = false
                        isLoading = true
                        Task { await loadTheme() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task { await loadTheme() }
        }
    }

    private var themedHTML: String {
        let base = """
        <style>
        body { margin: 0; padding: 16px; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
        img { max-width: 100%; height: auto; }
        table { border-collapse: collapse; width: 100%; }
        td, th { border: 1px solid #CCC; padding: 6px; }
        </style>
        """
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(themeCSS)</style>
        \(base)
        </head>
        <body>\(html)</body>
        </html>
        """
    }

    private func loadTheme() async {
        isLoading = true
        if !themeLoaded, let urlString = blog.url, let url = URL(string: urlString) {
            let css = await BlogThemeService.fetchThemeCSS(for: url)
            if !css.isEmpty {
                themeCSS = css
                themeLoaded = true
            }
        }
        isLoading = false
    }
}

private struct ThemedWebView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.isLoading == false {
            uiView.loadHTMLString(html, baseURL: nil)
        }
    }
}
