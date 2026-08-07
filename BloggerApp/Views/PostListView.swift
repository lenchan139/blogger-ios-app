import SwiftUI

struct PostListView: View {
    let blog: Blog
    @EnvironmentObject private var appState: AppState

    enum Filter: String, CaseIterable {
        case published, drafts
        var status: String { rawValue } // Blogger uses "live" & "draft"
    }

    @State private var filter: Filter = .published
    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLocalDrafts = false
    @State private var commentsPost: Post?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading posts…")
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Couldn't load posts", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }
                } else if posts.isEmpty {
                    ContentUnavailableView(
                        "No \(filter == .published ? "published" : "draft") posts",
                        systemImage: "doc.text"
                    )
                } else {
                    List(posts) { post in
                        NavigationLink {
                            PostEditorView(blog: blog, post: post)
                        } label: {
                            PostRow(post: post)
                        }
                        .contextMenu {
                            Button {
                                commentsPost = post
                            } label: {
                                Label("Comments", systemImage: "text.bubble")
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
            .navigationTitle(blog.name ?? "Posts")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases, id: \.self) { f in
                            Text(f == .published ? "Published" : "Drafts")
                        }
                    }
                    .pickerStyle(.segmented)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingLocalDrafts = true
                        } label: {
                            Label("Local drafts", systemImage: "externaldrive")
                        }
                        NavigationLink {
                            PostEditorView(blog: blog, post: nil)
                        } label: {
                            Label("New post", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showingLocalDrafts) {
                LocalDraftsView(blog: blog)
            }
            .sheet(item: $commentsPost) { post in
                NavigationStack {
                    CommentsView(blog: blog, post: post)
                }
            }
            .task(id: filter) { await load() }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let list = try await appState.api.listPosts(blogId: blog.id, status: filter.status)
            posts = list.items ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct PostRow: View {
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(post.title?.isEmpty == false ? post.title! : "Untitled")
                .font(.headline)
            if let updated = post.updated {
                Text("Updated \(Self.relative(updated))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let labels = post.labels, !labels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(labels, id: \.self) { label in
                            Text(label)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.tint.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private static func relative(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return "" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
