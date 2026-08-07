import SwiftUI

/// Lists locally saved unsaved drafts for a given blog so users can resume them.
struct LocalDraftsView: View {
    let blog: Blog
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

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
                            NavigationLink {
                                PostEditorView(blog: blog, post: nil, draft: draft)
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
                        }
                        .onDelete(perform: deleteDrafts)
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
        }
    }

    private func deleteDrafts(at offsets: IndexSet) {
        for index in offsets {
            let draft = drafts[index]
            appState.drafts.remove(id: draft.id)
        }
    }
}
