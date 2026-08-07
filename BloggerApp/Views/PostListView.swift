import SwiftUI

/// The posts section: lists the selected blog's posts, with a blog selector
/// (top-left) and a Google account switcher (top-right).
struct PostListView: View {
    @EnvironmentObject private var appState: AppState
    let blogs: [Blog]
    @Binding var selectedBlogId: String?

    enum Filter: String, CaseIterable {
        case all, published, drafts, locals
        // Blogger's status query param: "live" for published, "draft" for drafts,
        // nil for "all" (no filter) and "locals" (not an API call).
        var status: String? {
            switch self {
            case .all, .locals: return nil
            case .published: return "live"
            case .drafts: return "draft"
            }
        }
        var title: String {
            switch self {
            case .all: return "All"
            case .published: return "Published"
            case .drafts: return "Drafts"
            case .locals: return "Local"
            }
        }
    }

    @State private var filter: Filter = .published
    @State private var postsByFilter: [Filter: [Post]] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var commentsPost: Post?
    @State private var labelPost: Post?
    @State private var labelDraftLabels: [String] = []
    @State private var discardPost: Post?
    @State private var previewItem: WebPreviewItem?
    @State private var showNewPost = false

    private var selectedBlog: Blog? {
        blogs.first { $0.id == selectedBlogId } ?? blogs.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if let blog = selectedBlog {
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
                    Button {
                        showNewPost = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New post")
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
            .sheet(isPresented: $showNewPost) {
                if let blog = selectedBlog {
                    NavigationStack { PostEditorView(blog: blog, post: nil) }
                }
            }
            .task(id: selectedBlogId) {
                guard selectedBlog != nil else { return }
                postsByFilter = [:]
                await loadPosts()
            }
            .onChange(of: selectedBlog?.id) { _, _ in
                postsByFilter = [:]
            }
            .sheet(item: $commentsPost) { post in
                if let blog = selectedBlog {
                    NavigationStack {
                        CommentsView(blog: blog, post: post)
                    }
                }
            }
            .sheet(item: $labelPost) { post in
                if let blog = selectedBlog {
                    NavigationStack {
                        LabelsEditSheet(
                            title: post.title ?? "Untitled",
                            labels: $labelDraftLabels,
                            onSave: {
                                Task { await saveLabels(for: post, labels: labelDraftLabels) }
                            }
                        )
                    }
                }
            }
            .sheet(item: $previewItem) { item in
                NavigationStack {
                    WebPreviewView(url: item.url)
                        .navigationTitle("Preview")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .confirmationDialog(
                "Discard this post? This permanently deletes it.",
                isPresented: discardBinding,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) {
                    if let post = discardPost {
                        Task { await deletePost(post) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var discardBinding: Binding<Bool> {
        Binding(
            get: { discardPost != nil },
            set: { if !$0 { discardPost = nil } }
        )
    }

    @ViewBuilder
    private func postList(for blog: Blog) -> some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { f in
                    Text(f.title)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            TabView(selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { f in
                    postsPage(for: blog, filter: f)
                        .tag(f)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func postsPage(for blog: Blog, filter: Filter) -> some View {
        if filter == .locals {
            localDraftsPage(for: blog)
        } else {
            apiPostsPage(for: blog, filter: filter)
        }
    }

    @ViewBuilder
    private func localDraftsPage(for blog: Blog) -> some View {
        let drafts = appState.drafts.drafts.filter { $0.blogId == blog.id }
        if drafts.isEmpty {
            ContentUnavailableView(
                "No local drafts",
                systemImage: "externaldrive",
                description: Text("Unsaved edits are saved here automatically.")
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
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func apiPostsPage(for blog: Blog, filter: Filter) -> some View {
        let posts = postsByFilter[filter] ?? []
        if posts.isEmpty {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No \(filter == .published ? "published" : "draft") posts",
                    systemImage: "doc.text"
                )
            }
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
                    Button {
                        Task { await togglePublish(post) }
                    } label: {
                        if post.status == .draft {
                            Label("Publish", systemImage: "paperplane.fill")
                        } else {
                            Label("Revert to draft", systemImage: "arrow.uturn.backward")
                        }
                    }
                    Button {
                        labelPost = post
                        labelDraftLabels = post.labels ?? []
                    } label: {
                        Label("Apply labels", systemImage: "tag")
                    }
                    Button {
                        if let urlString = post.url, let url = URL(string: urlString) {
                            previewItem = WebPreviewItem(url: url)
                        }
                    } label: {
                        Label("Preview", systemImage: "eye")
                    }
                    if let urlString = post.url, let url = URL(string: urlString) {
                        ShareLink(item: url) {
                            Label("Share link", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button(role: .destructive) {
                        discardPost = post
                    } label: {
                        Label("Discard post", systemImage: "trash")
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await loadPosts(for: filter) }
            .overlay(alignment: .top) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 4)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isLoading)
        }
    }

    private func loadPosts() async {
        guard selectedBlog != nil else { return }
        for filter in Filter.allCases where filter != .locals {
            await loadPosts(for: filter)
        }
    }

    private func loadPosts(for filter: Filter) async {
        guard let blog = selectedBlog else { return }
        if filter == .locals { return }
        isLoading = true
        errorMessage = nil
        do {
            let list = try await appState.api.listPosts(blogId: blog.id, status: filter.status)
            postsByFilter[filter] = list.items ?? []
        } catch {
            // Pull-to-refresh can cancel the in-flight task; that's not an error.
            if Task.isCancelled { return }
            if let urlErr = error as? URLError, urlErr.code == .cancelled { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Post actions

    private func togglePublish(_ post: Post) async {
        guard let blog = selectedBlog else { return }
        do {
            if post.status == .draft {
                _ = try await appState.api.publishPost(blogId: blog.id, postId: post.id)
            } else {
                _ = try await appState.api.revertPost(blogId: blog.id, postId: post.id)
            }
            await loadPosts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveLabels(for post: Post, labels: [String]) async {
        guard let blog = selectedBlog else { return }
        var patched = post
        patched.labels = labels.isEmpty ? nil : labels
        do {
            _ = try await appState.api.patchPost(patched, blogId: blog.id)
            labelPost = nil
            await loadPosts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePost(_ post: Post) async {
        guard let blog = selectedBlog else { return }
        do {
            try await appState.api.deletePost(blogId: blog.id, postId: post.id)
            discardPost = nil
            appState.drafts.removeForPost(blogId: blog.id, postId: post.id)
            await loadPosts()
        } catch {
            errorMessage = error.localizedDescription
        }
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

// MARK: - Labels editor

/// Edits a post's labels in a sheet.
struct LabelsEditSheet: View {
    let title: String
    @Binding var labels: [String]
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newLabel = ""

    var body: some View {
        Form {
            Section("Post") {
                Text(title)
                    .font(.subheadline)
            }
            Section("Labels") {
                ForEach(labels, id: \.self) { label in
                    HStack {
                        Text(label)
                        Spacer()
                        Button {
                            labels.removeAll { $0 == label }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    TextField("Add a label", text: $newLabel)
                    Button("Add") {
                        let trimmed = newLabel.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            labels.append(trimmed)
                            newLabel = ""
                        }
                    }
                    .disabled(newLabel.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle("Apply labels")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave()
                }
                .bold()
            }
        }
    }
}

// MARK: - Web preview

/// Simple WKWebView wrapper for previewing a post.
import WebKit

struct WebPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct WebPreviewView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.load(URLRequest(url: url))
    }
}
