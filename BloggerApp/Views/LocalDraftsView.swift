import SwiftUI

/// Lists locally saved unsaved drafts for a given blog so users can resume them.
struct LocalDraftsView: View {
    let blog: Blog
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var editingDraft: LocalDraft?
    @State private var draftPendingDelete: LocalDraft?

    private var drafts: [LocalDraft] {
        appState.drafts.drafts.filter { $0.blogId == blog.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if drafts.isEmpty {
                    ContentUnavailableView(
                        "No local drafts",
                        systemImage: "externaldrive.badge.xmark",
                        description: Text("Unsaved edits are stored here automatically.")
                    )
                } else {
                    List {
                        ForEach(drafts) { draft in
                            Button {
                                editingDraft = draft
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(draft.title.isEmpty ? "Untitled draft" : draft.title)
                                        .font(.headline)
                                    Text("Edited \(draft.updatedAt.formatted(.relative(presentation: .named)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !draft.labels.isEmpty {
                                        Text(draft.labels.joined(separator: ", "))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    draftPendingDelete = draft
                                } label: {
                                    Label("Delete draft", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Local drafts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingDraft) { draft in
                NavigationStack { PostEditorView(blog: blog, post: nil, draft: draft) }
            }
            .alert("Delete draft?", isPresented: .init(
                get: { draftPendingDelete != nil },
                set: { if !$0 { draftPendingDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let draft = draftPendingDelete {
                        draftPendingDelete = nil
                        appState.drafts.remove(id: draft.id)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes the local draft. This action cannot be undone.")
            }
        }
    }
}
