import Foundation

/// A locally persisted draft so unsaved editor content survives app relaunch
/// or crash (fixing the "lost post" gap in the official Android app).
struct LocalDraft: Codable, Identifiable, Equatable {
    var id: String           // "new-<uuid>" for drafts, or the post id for edits
    var blogId: String
    var postId: String?      // nil for brand-new posts
    var title: String
    var html: String
    var labels: [String]
    var updatedAt: Date
}

/// Persists drafts as JSON files in the Application Support directory.
@MainActor
final class LocalDraftStore: ObservableObject {
    @Published private(set) var drafts: [LocalDraft] = []

    private let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = base.appendingPathComponent("LocalDrafts", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        loadAll()
    }

    private func fileURL(for id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
    }

    func draft(for id: String) -> LocalDraft? {
        drafts.first { $0.id == id }
    }

    func upsert(_ draft: LocalDraft) {
        if let idx = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[idx] = draft
        } else {
            drafts.append(draft)
        }
        drafts.sort { $0.updatedAt > $1.updatedAt }
        persist(draft)
    }

    func remove(id: String) {
        drafts.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }

    func removeForPost(blogId: String, postId: String) {
        let matches = drafts.filter { $0.blogId == blogId && $0.postId == postId }
        for m in matches { remove(id: m.id) }
    }

    func removeForBlog(blogId: String) {
        for d in drafts where d.blogId == blogId { remove(id: d.id) }
    }

    private func persist(_ draft: LocalDraft) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        try? data.write(to: fileURL(for: draft.id), options: .atomic)
    }

    private func loadAll() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        var loaded: [LocalDraft] = []
        for url in urls where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let draft = try? JSONDecoder().decode(LocalDraft.self, from: data) {
                loaded.append(draft)
            }
        }
        loaded.sort { $0.updatedAt > $1.updatedAt }
        drafts = loaded
    }
}
