import SwiftUI
import UIKit

struct ParagraphBlockView: View {
    @Binding var content: String

    var body: some View {
        HTMLTextView(html: $content)
    }
}

struct HeadingBlockView: View {
    let level: Int
    @Binding var content: String

    private var font: UIFont {
        let style: UIFont.TextStyle = {
            switch level {
            case 1: return .largeTitle
            case 2: return .title1
            case 3: return .title2
            case 4: return .title3
            case 5: return .headline
            default: return .subheadline
            }
        }()
        return .preferredFont(forTextStyle: style)
    }

    var body: some View {
        HTMLTextView(html: $content, font: font)
    }
}

struct QuoteBlockView: View {
    @Binding var content: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.6))
                .frame(width: 3)
            HTMLTextView(html: $content, font: .preferredFont(forTextStyle: .body))
        }
    }
}

struct CodeBlockView: View {
    @Binding var content: String

    var body: some View {
        GrowingTextEditor(
            text: $content,
            font: .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        )
        .padding(8)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct DividerBlockView: View {
    var body: some View {
        Divider()
            .frame(height: 1)
            .padding(.vertical, 8)
    }
}

struct CustomHTMLBlockView: View {
    @Binding var content: String

    var body: some View {
        GrowingTextEditor(
            text: $content,
            font: .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        )
        .padding(8)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topLeading) {
            Text("Custom HTML")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.thinMaterial, in: Capsule())
                .padding(4)
        }
    }
}