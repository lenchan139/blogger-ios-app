import SwiftUI

/// Gutenberg-style per-block settings sheet. Type-specific controls for the
/// currently selected block.
struct BlockInspectorView: View {
    @Binding var block: Block
    @ObservedObject var state: EditorState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Block type") {
                    Picker("Type", selection: typeBinding) {
                        Text("Paragraph").tag(BlockTypeChoice.paragraph)
                        Text("Heading").tag(BlockTypeChoice.heading)
                        Text("List (bullet)").tag(BlockTypeChoice.listBullet)
                        Text("List (numbered)").tag(BlockTypeChoice.listNumber)
                        Text("Quote").tag(BlockTypeChoice.quote)
                        Text("Code").tag(BlockTypeChoice.code)
                        Text("Divider").tag(BlockTypeChoice.divider)
                    }
                    if case .heading = block.type {
                        Picker("Level", selection: levelBinding) {
                            ForEach(1..<7) { Text("H\($0)").tag($0) }
                        }
                    }
                }

                switch block.type {
                case .image:
                    imageSection
                case .heading, .paragraph, .quote:
                    Text("Inline formatting is available from the toolbar while editing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                default:
                    EmptyView()
                }

                Section {
                    Button("Move up") { move(-1) }
                    Button("Move down") { move(1) }
                    Button("Duplicate") { state.duplicate(block.id); dismiss() }
                    Button("Delete block", role: .destructive) {
                        state.remove(block.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder private var imageSection: some View {
        Section("Image") {
            TextField("Image URL", text: urlBinding)
                .keyboardType(.URL)
                .autocorrectionDisabled()
            TextField("Alt text", text: altBinding)
            TextField("Caption", text: captionBinding, axis: .vertical)
        }
    }

    // MARK: - Bindings

    private enum BlockTypeChoice: Hashable {
        case paragraph, heading, listBullet, listNumber, quote, code, divider
    }

    private var typeBinding: Binding<BlockTypeChoice> {
        Binding(
            get: {
                switch block.type {
                case .paragraph: return .paragraph
                case .heading: return .heading
                case .list(false): return .listBullet
                case .list(true): return .listNumber
                case .quote: return .quote
                case .code: return .code
                case .divider: return .divider
                default: return .paragraph
                }
            },
            set: { choice in
                let new: BlockType
                switch choice {
                case .paragraph: new = .paragraph
                case .heading: new = .heading(level: 2)
                case .listBullet: new = .list(ordered: false)
                case .listNumber: new = .list(ordered: true)
                case .quote: new = .quote
                case .code: new = .code
                case .divider: new = .divider
                }
                state.changeType(block.id, to: new)
            }
        )
    }

    private var levelBinding: Binding<Int> {
        Binding(
            get: { if case .heading(let l) = block.type { return l }; return 2 },
            set: { state.changeType(block.id, to: .heading(level: $0)) }
        )
    }

    private var urlBinding: Binding<String> {
        Binding(get: { block.content }, set: { v in state.update(block.id) { $0.content = v } })
    }
    private var altBinding: Binding<String> {
        Binding(get: { block.attributes["alt"] ?? "" }, set: { v in state.update(block.id) { $0.attributes["alt"] = v } })
    }
    private var captionBinding: Binding<String> {
        Binding(
            get: { block.attributes["caption"] ?? "" },
            set: { v in state.update(block.id) { $0.attributes["caption"] = v } }
        )
    }

    private func move(_ delta: Int) {
        guard let i = state.blocks.firstIndex(of: block) else { return }
        let dest = i + delta + (delta > 0 ? 1 : 0)
        guard state.blocks.indices.contains(dest) || dest == state.blocks.count else { return }
        state.move(from: i, to: dest)
    }
}