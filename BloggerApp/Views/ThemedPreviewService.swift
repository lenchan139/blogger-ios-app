import Foundation

/// Fetches a blog's theme CSS from its public page so previews match the real
/// blog styling (fonts, colors, link styles).
enum BlogThemeService {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    /// Downloads the blog's homepage and extracts its theme CSS (inline
    /// `<style>` blocks plus linked stylesheets). Returns an empty string on
    /// failure so callers can fall back to default styling.
    static func fetchThemeCSS(for blogURL: URL) async -> String {
        guard let (data, _) = try? await session.data(from: blogURL),
              let html = String(data: data, encoding: .utf8) else {
            return ""
        }

        var cssParts: [String] = []

        // Inline <style> blocks.
        if let styleRegex = try? NSRegularExpression(pattern: "<style[^>]*>([\\s\\S]*?)</style>", options: [.caseInsensitive]) {
            let ns = html as NSString
            let matches = styleRegex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))
            for match in matches {
                let range = match.range(at: 1)
                guard range.location != NSNotFound else { continue }
                cssParts.append(ns.substring(with: range))
            }
        }

        // Linked stylesheets (best effort — fetch each).
        if let linkRegex = try? NSRegularExpression(
            pattern: "<link[^>]*rel=[\"']stylesheet[\"'][^>]*href=[\"']([^\"']+)[\"']",
            options: [.caseInsensitive]
        ) {
            let ns = html as NSString
            let matches = linkRegex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))
            for match in matches {
                let range = match.range(at: 1)
                guard range.location != NSNotFound else { continue }
                let href = ns.substring(with: range)
                guard let url = URL(string: href, relativeTo: blogURL) else { continue }
                if let (cssData, _) = try? await session.data(from: url),
                   let css = String(data: cssData, encoding: .utf8) {
                    cssParts.append(css)
                }
            }
        }

        return cssParts.joined(separator: "\n")
    }
}
