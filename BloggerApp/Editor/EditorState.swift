import Foundation
import SwiftUI

/// Holds the live block list and notifies the host (via `onChange`) whenever the
/// serialized HTML changes. This is the single source of truth for the block
/// editor; the host's `html` binding stays in sync through `emit()`.
@MainActor
final class EditorState: ObservableObject {
    @Published var blocks: [Block]
    @Published var selectedID: UUID?

    /// Called with the freshly-serialized HTML whenever blocks change.
    var onChange: ((String) -> Void)?

    init(html: String) {
        self.blocks = BlockHTMLCodec.decode(html)
    }

    // MARK: - Mutation

    func update(_ id: UUID, _ change: (inout Block) -> Void) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        change(&blocks[index])
        emit()
    }

    func append(_ type: BlockType, after id: UUID? = nil) {
        let new = Block(type: type)
        if let id, let index = blocks.firstIndex(where: { $0.id == id }) {
            blocks.insert(new, at: index + 1)
        } else {
            blocks.append(new)
        }
        selectedID = new.id
        emit()
    }

    func remove(_ id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks.remove(at: index)
        if blocks.isEmpty { blocks.append(.init(type: .paragraph)) }
        emit()
    }

    func move(from source: Int, to destination: Int) {
        guard blocks.indices.contains(source) else { return }
        var removed = blocks.remove(at: source)
        let insertIndex = destination > source ? destination - 1 : destination
        let clamped = min(max(insertIndex, 0), blocks.count)
        blocks.insert(removed, at: clamped)
        _ = removed
        emit()
    }

    func duplicate(_ id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        let copy = Block(id: UUID(), type: blocks[index].type, content: blocks[index].content, attributes: blocks[index].attributes)
        blocks.insert(copy, at: index + 1)
        selectedID = copy.id
        emit()
    }

    func changeType(_ id: UUID, to type: BlockType) {
        update(id) { $0.type = type }
    }

    // MARK: - Image upload

    /// Appends a placeholder image block with an "uploading" state.
    func beginImageUpload() {
        let pending = Block(type: .image, content: "", attributes: ["uploadState": "uploading"])
        blocks.append(pending)
        pendingImageID = pending.id
        selectedID = pending.id
        emit()
    }

    /// Fills the pending image block with the uploaded URL.
    func finishImageUpload(url: String, caption: String, alt: String?) {
        guard let pendingID = pendingImageID, let index = blocks.firstIndex(where: { $0.id == pendingID }) else {
            return
        }
        var updated = blocks[index]
        updated.content = url
        updated.attributes["uploadState"] = "ready"
        if !caption.isEmpty { updated.attributes["caption"] = caption }
        if let alt, !alt.isEmpty { updated.attributes["alt"] = alt }
        blocks[index] = updated
        pendingImageID = nil
        emit()
    }

    private(set) var pendingImageID: UUID?

    // MARK: - HTML sync

    func emit() {
        let html = BlockHTMLCodec.encode(blocks)
        onChange?(html)
    }
}