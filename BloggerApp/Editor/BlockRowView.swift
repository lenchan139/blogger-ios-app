import SwiftUI
import UIKit

/// Renders a single block and hosts its editing surface. Long-press offers
/// the block menu (move, duplicate, delete, change type); tapping selects.
struct BlockRowView: View {
    @Binding var block: Block
    @ObservedObject var state: EditorState
    let isSelected: Bool

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { state.selectedID = block.id }
            .contextMenu {
                blockMenu
            }
            .sheet(isPresented: $showInspector) {
                BlockInspectorView(block: $block, state: state)
            }
    }

    @State private var showInspector = false

    @ViewBuilder private var content: some View {
        switch block.type {
        case .paragraph:
            ParagraphBlockView(content: blockContentBinding)
        case .heading(let level):
            HeadingBlockView(level: level, content: blockContentBinding)
        case .list(let ordered):
            ListBlockView(ordered: ordered, content: blockContentBinding)
        case .quote:
            QuoteBlockView(content: blockContentBinding)
        case .code:
            CodeBlockView(content: blockContentBinding)
        case .image:
            ImageBlockView(block: $block)
        case .divider:
            DividerBlockView()
        case .customHTML:
            CustomHTMLBlockView(content: blockContentBinding)
        }
    }

    /// Binding to the block's inline content that mutates via state so HTML is
    /// re-emitted through `.onChange(of: state.blocks)`.
    private var blockContentBinding: Binding<String> {
        Binding(
            get: { block.content },
            set: { newValue in state.update(block.id) { $0.content = newValue } }
        )
    }

    @ViewBuilder private var blockMenu: some View {
        Menu("Change to") {
            Button("Paragraph") { state.changeType(block.id, to: .paragraph) }
            ForEach(1..<7) { lvl in
                Button("Heading \(lvl)") { state.changeType(block.id, to: .heading(level: lvl)) }
            }
            Button("List (bullet)") { state.changeType(block.id, to: .list(ordered: false)) }
            Button("List (numbered)") { state.changeType(block.id, to: .list(ordered: true)) }
            Button("Quote") { state.changeType(block.id, to: .quote) }
            Button("Code") { state.changeType(block.id, to: .code) }
            Button("Divider") { state.changeType(block.id, to: .divider) }
        }
        Button("Settings…") { showInspector = true }
        Divider()
        Button("Move up") {
            if let i = state.blocks.firstIndex(of: block), i > 0 {
                state.move(from: i, to: i - 1)
            }
        }
        Button("Move down") {
            if let i = state.blocks.firstIndex(of: block), i < state.blocks.count - 1 {
                state.move(from: i, to: i + 2)
            }
        }
        Button("Duplicate", systemImage: "plus.square.on.square") { state.duplicate(block.id) }
        Button("Delete", role: .destructive) { state.remove(block.id) }
    }
}