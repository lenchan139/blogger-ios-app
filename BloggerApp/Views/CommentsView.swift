import SwiftUI

/// Moderate comments for a single post.
struct CommentsView: View {
    let blog: Blog
    let post: Post
    @EnvironmentObject private var appState: AppState

    @State private var comments: [Comment] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
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
                    CommentRow(comment: comment) { action in
                        if action == .delete {
                            commentPendingDelete = comment
                        } else {
                            Task { await perform(action, on: comment) }
                        }
                    }
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle("Comments")
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

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let list = try await appState.api.listComments(blogId: blog.id, postId: post.id)
            comments = list.items ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func perform(_ action: CommentRow.Action, on comment: Comment) async {
        do {
            switch action {
            case .approve:
                _ = try await appState.api.approveComment(blogId: blog.id, postId: post.id, commentId: comment.id)
            case .markSpam:
                _ = try await appState.api.markCommentAsSpam(blogId: blog.id, postId: post.id, commentId: comment.id)
            case .removeContent:
                _ = try await appState.api.removeCommentContent(blogId: blog.id, postId: post.id, commentId: comment.id)
            case .delete:
                try await appState.api.deleteComment(blogId: blog.id, postId: post.id, commentId: comment.id)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Row for a comment with moderation actions.
struct CommentRow: View {
    enum Action {
        case approve, markSpam, removeContent, delete
    }

    let comment: Comment
    let onAction: (Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(comment.author?.displayName ?? "Anonymous")
                    .font(.subheadline.bold())
                Spacer()
                if let status = comment.status {
                    Text(status.rawValue.capitalized)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color(for: status).opacity(0.15), in: Capsule())
                        .foregroundStyle(color(for: status))
                }
            }
            Text(comment.content ?? "")
                .font(.body)
                .lineLimit(4)
            if let published = comment.published {
                Text(Self.relative(published))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if comment.status == .spam {
                    Button("Approve") { onAction(.approve) }
                }
                Button("Spam") { onAction(.markSpam) }
                Button("Remove content") { onAction(.removeContent) }
                Button(role: .destructive) {
                    onAction(.delete)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .font(.footnote)
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    private func color(for status: Comment.CommentStatus) -> Color {
        switch status {
        case .live: return .green
        case .spam: return .red
        case .pending, .awaitingModeration: return .orange
        }
    }

    private static func relative(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return "" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
