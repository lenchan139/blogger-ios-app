import SwiftUI

/// Gutenberg-style formatting bar shown above the keyboard while editing a
/// rich-text block (paragraph, heading, quote).
struct BlockFormatToolbar: View {
    @Binding var showLinkSheet: Bool

    var body: some View {
        HStack(spacing: 18) {
            Button { RichTextFormatting.toggleBold() } label: {
                Image(systemName: "bold").font(.body)
            }
            Button { RichTextFormatting.toggleItalic() } label: {
                Image(systemName: "italic").font(.body)
            }
            Button { RichTextFormatting.toggleUnderline() } label: {
                Image(systemName: "underline").font(.body)
            }
            Button { RichTextFormatting.toggleStrikethrough() } label: {
                Image(systemName: "strikethrough").font(.body)
            }
            Button { showLinkSheet = true } label: {
                Image(systemName: "link").font(.body)
            }
            Spacer()
            Text("Block editor")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

/// Link input for the selected range (ported from the legacy `LinkInputView`).
struct BlockLinkInputView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var url = "https://"
    @State private var title = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Link text (optional)", text: $title)
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
                            RichTextFormatting.addLink(linkURL, title: title)
                        }
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}