import SwiftUI
import UIKit
import InfomaniakRichHTMLEditor

/// An Apple Notes–style rich HTML editor: a clean, plain editing surface with
/// the formatting controls in the keyboard accessory bar (invoked via an "Aa"
/// button), backed by the Infomaniak editor (renders tables + images natively).
struct RichTextEditor: View {
    @Binding var html: String
    @StateObject private var textAttributes: TextAttributes
    @StateObject private var router: EditorRouter
    private let accessoryView: UIView

    init(html: Binding<String>) {
        _html = html
        let textAttributes = TextAttributes()
        let router = EditorRouter()
        _textAttributes = StateObject(wrappedValue: textAttributes)
        _router = StateObject(wrappedValue: router)

        let controller = UIHostingController(
            rootView: AccessoryToolbar(textAttributes: textAttributes, router: router)
        )
        controller.view.backgroundColor = .clear
        controller.view.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44)
        accessoryView = controller.view
    }

    var body: some View {
        RichHTMLEditor(html: $html, textAttributes: textAttributes)
            .editorScrollable(true)
            .editorCSS(editorCSS)
            .editorInputAccessoryView(accessoryView)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $router.showLinkSheet) {
                LinkInputView(textAttributes: textAttributes)
            }
    }

    private var editorCSS: String {
        """
        :root {
            --paragraph-spacing: 1em;
            --sl-color-border: #CCC;
            --sl-color-hairline: #DDD;
            --sl-text-sm: 14px;
            --sl-text-code-sm: 14px;
        }
        #swift-rich-html-editor { font-family: -apple-system, BlinkMacSystemFont, sans-serif; font-size: 17px; line-height: 1.5; padding: 8px; }
        img { max-width: 100%; height: auto; }
        #swift-rich-html-editor table { display: table !important; border-collapse: collapse; width: 100%; max-width: 100%; }
        #swift-rich-html-editor table tr { display: table-row !important; }
        #swift-rich-html-editor table td, #swift-rich-html-editor table th { display: table-cell !important; border: 1px solid #CCC; padding: 6px; }
        """
    }
}

/// Shared state between the editor and its accessory toolbar.
final class EditorRouter: ObservableObject {
    @Published var showLinkSheet = false
}

// MARK: - Apple Notes style accessory toolbar

private struct AccessoryToolbar: View {
    @ObservedObject var textAttributes: TextAttributes
    @ObservedObject var router: EditorRouter

    @State private var expanded = false

    var body: some View {
        HStack(spacing: 2) {
            // Notes-style "Aa" button toggles the formatting panel.
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                Image(systemName: "textformat.size")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 34, height: 30)
                    .foregroundStyle(expanded ? Color.accentColor : Color.primary)
                    .background(expanded ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            if expanded {
                toolButton("bold", active: textAttributes.hasBold) { textAttributes.bold() }
                toolButton("italic", active: textAttributes.hasItalic) { textAttributes.italic() }
                toolButton("underline", active: textAttributes.hasUnderline) { textAttributes.underline() }
                toolButton("strikethrough", active: textAttributes.hasStrikethrough) { textAttributes.strikethrough() }
                divider
                toolButton("list.bullet", active: textAttributes.hasUnorderedList) { textAttributes.unorderedList() }
                toolButton("list.number", active: textAttributes.hasOrderedList) { textAttributes.orderedList() }
                divider
                toolButton("link", active: textAttributes.hasLink) { router.showLinkSheet = true }
                divider
                toolButton("arrow.uturn.backward") { textAttributes.undo() }
                toolButton("arrow.uturn.forward") { textAttributes.redo() }
            }

            Spacer(minLength: 0)
        }
        .frame(height: 44)
        .padding(.horizontal, 8)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }

    private func toolButton(_ systemName: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 32, height: 30)
                .foregroundStyle(active ? Color.accentColor : Color.primary)
                .background(active ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .leading).combined(with: .opacity))
    }
}

// MARK: - Link input

private struct LinkInputView: View {
    @ObservedObject var textAttributes: TextAttributes
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
                            let label = text.isEmpty ? nil : text
                            textAttributes.addLink(url: linkURL, text: label)
                        }
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}
