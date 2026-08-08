import SwiftUI

/// The block editor surface: a vertical stack of blocks plus an "appender".
/// HTML is decoded into blocks once (on init); every mutation re-encodes and
/// pushes the new HTML up through the `html` binding so the host's existing
/// autosave / preview / publish flow is untouched.
struct BlockEditorView: View {
    @Binding var html: String
    @StateObject private var state: EditorState
    @State private var showLinkSheet = false

    init(html: Binding<String>) {
        _html = html
        _state = StateObject(wrappedValue: EditorState(html: html.wrappedValue))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach($state.blocks) { $block in
                    BlockRowView(block: $block, state: state, isSelected: state.selectedID == block.id)
                }
                appender
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                BlockFormatToolbar(showLinkSheet: $showLinkSheet)
            }
        }
        .sheet(isPresented: $showLinkSheet) {
            BlockLinkInputView()
        }
        .onReceive(NotificationCenter.default.publisher(for: BlockEditorNotifications.imageUploadBegan)) { _ in
            state.beginImageUpload()
        }
        .onReceive(NotificationCenter.default.publisher(for: BlockEditorNotifications.imageUploadFinished)) { note in
            let url = note.userInfo?["url"] as? String ?? ""
            let caption = note.userInfo?["caption"] as? String ?? ""
            let alt = note.userInfo?["alt"] as? String
            state.finishImageUpload(url: url, caption: caption, alt: alt)
        }
        .onAppear {
            state.onChange = { new in
                if new != html { html = new }
            }
            state.emit()
        }
        .onChange(of: state.blocks) { _, _ in
            state.emit()
        }
    }

    private var appender: some View {
        Button {
            state.append(.paragraph)
        } label: {
            Label("Add block", systemImage: "plus.circle.dashed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}