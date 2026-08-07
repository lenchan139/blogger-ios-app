import SwiftUI

/// Home screen: lists the selected blog's posts, with a blog selector (top-left)
/// and a Google account switcher (top-right).
struct PostListView: View {
    @EnvironmentObject private var appState: AppState

    enum Filter: String, CaseIterable {
        case published, drafts
        // Blogger's status query param uses "live" for published posts.
        var status: String { self == .published ? "live" : "draft" }
    }

    @State private var filter: Filter = .published
    @State private var blogs: [Blog] = []
    @State private var selectedBlogId: String?
    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLocalDrafts = false
    @State private var commentsPost: Post?

    private var selectedBlog: Blog? {
        blogs.first { $0.id == selectedBlogId } ?? blogs.first
    }

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
                        Button("Retry") { Task { await loadBlogs() } }
                    }
                } else if let blog = selectedBlog {
                    postList(for: blog)
                } else {
                    ContentUnavailableView("No blogs", systemImage: "doc.text")
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if blogs.count > 1 {
                        Menu {
                            ForEach(blogs) { blog in
                                Button {
                                    selectedBlogId = blog.id
                                } label: {
                                    if blog.id == selectedBlog?.id {
                                        Label(blog.name ?? "Untitled", systemImage: "checkmark")
                                    } else {
                                        Text(blog.name ?? "Untitled")
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(selectedBlog?.name ?? "Select blog")
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.caption2.bold())
                            }
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(.quaternary, lineWidth: 1)
                            )
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        if let blog = selectedBlog {
                            NavigationLink {
                                BlogInfoView(blog: blog)
                            } label: {
                                Label("Blog info", systemImage: "info.circle")
                            }
                            NavigationLink {
                                PagesListView(blog: blog)
                            } label: {
                                Label("Pages", systemImage: "doc.plaintext")
                            }
                            NavigationLink {
                                AllCommentsView(blog: blog)
                            } label: {
                                Label("All comments", systemImage: "text.bubble")
                            }
                            NavigationLink {
                                StatsView(blog: blog)
                            } label: {
                                Label("Stats", systemImage: "chart.bar")
                            }
                        }
                        Button {
                            showingLocalDrafts = true
                        } label: {
                            Label("Local drafts", systemImage: "externaldrive")
                        }
                        NavigationLink {
                            if let blog = selectedBlog {
                                PostEditorView(blog: blog, post: nil)
                            } else {
                                Text("Select a blog first")
                            }
                        } label: {
                            Label("New post", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    Menu {
                        if let email = appState.userEmail {
                            Text(email)
                                .font(.caption)
                        }
                        Button {
                            Task { await appState.switchAccount() }
                        } label: {
                            Label("Switch account", systemImage: "person.crop.circle.badge.plus")
                        }
                        Button(role: .destructive) {
                            appState.signOut()
                        } label: {
                            Label("Sign out", systemImage: "arrow.right.square")
                        }
                    } label: {
                        AccountAvatarView(url: appState.userAvatarURL)
                    }
                }
            }
            .task { await loadBlogs() }
            .task(id: selectedBlogId) {
                guard selectedBlog != nil else { return }
                await loadPosts()
            }
            .task(id: filter) {
                guard selectedBlog != nil else { return }
                await loadPosts()
            }
            .onChange(of: selectedBlog?.id) { _, _ in
                posts = []
            }
            .sheet(isPresented: $showingLocalDrafts) {
                if let blog = selectedBlog {
                    LocalDraftsView(blog: blog)
                }
            }
            .sheet(item: $commentsPost) { post in
                if let blog = selectedBlog {
                    NavigationStack {
                        CommentsView(blog: blog, post: post)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func postList(for blog: Blog) -> some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { f in
                    Text(f == .published ? "Published" : "Drafts")
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if posts.isEmpty {
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
                .refreshable { await loadPosts() }
            }
        }
    }

    private func loadBlogs() async {
        errorMessage = nil
        do {
            let list = try await appState.api.listUserBlogs()
            blogs = list.items ?? []
            if selectedBlogId == nil {
                selectedBlogId = blogs.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadPosts() async {
        guard let blog = selectedBlog else { return }
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
