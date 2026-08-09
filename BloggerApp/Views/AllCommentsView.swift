import SwiftUI

/// Moderates all comments across a blog's posts (via the listByBlog endpoint).
struct AllCommentsView: View {
    let blog: Blog
    @EnvironmentObject private var appState: AppState

    @State private var comments: [Comment] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var postTitles: [String: String] = [:]
    @State private var commentPendingDelete: Comment?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading comments…")
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Couldn't load comments", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
            } else if comments.isEmpty {
                ContentUnavailableView("No comments", systemImage: "text.bubble")
            } else {
                List(comments) { comment in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("On: \(postTitle(comment) ?? "unknown post")")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        CommentRow(comment: comment) { action in
                            if action == .delete {
                                commentPendingDelete = comment
                            } else {
                                Task { await perform(action, on: comment) }
                            }
                        }
                    }
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle("All comments")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete comment?", isPresented: .init(
            get: { commentPendingDelete != nil },
            set: { if !$0 { commentPendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let comment = commentPendingDelete {
                    commentPendingDelete = nil
                    Task { await perform(.delete, on: comment) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the comment. This action cannot be undone.")
        }
        .task { await load() }
    }

    private func postTitle(_ comment: Comment) -> String? {
        postTitles[comment.post?.id ?? ""]
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let list = try await appState.api.listCommentsByBlog(blogId: blog.id)
            comments = list.items ?? []
            await loadPostTitles(for: comments)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadPostTitles(for comments: [Comment]) async {
        var titles: [String: String] = [:]
        for comment in comments {
            guard let postId = comment.post?.id else { continue }
            if let post = try? await appState.api.getPost(blogId: blog.id, postId: postId, fetchBodies: false) {
                titles[postId] = post.title
            }
        }
        postTitles = titles
    }

    private func perform(_ action: CommentRow.Action, on comment: Comment) async {
        guard let postId = comment.post?.id else { return }
        do {
            switch action {
            case .approve:
                _ = try await appState.api.approveComment(blogId: blog.id, postId: postId, commentId: comment.id)
            case .markSpam:
                _ = try await appState.api.markCommentAsSpam(blogId: blog.id, postId: postId, commentId: comment.id)
            case .removeContent:
                _ = try await appState.api.removeCommentContent(blogId: blog.id, postId: postId, commentId: comment.id)
            case .delete:
                try await appState.api.deleteComment(blogId: blog.id, postId: postId, commentId: comment.id)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
