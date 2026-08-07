import SwiftUI

struct BlogSwitcherView: View {
    @EnvironmentObject private var appState: AppState
    @State private var blogs: [Blog] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedBlogId: String?

    private var selectedBlog: Blog? {
        blogs.first { $0.id == selectedBlogId }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading your blogs…")
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Couldn't load blogs", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }
                } else {
                    List(blogs) { blog in
                        Button {
                            selectedBlogId = blog.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(blog.name ?? "Untitled blog")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(blog.url ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(blog.posts?.totalItems ?? 0) posts")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                if blog.id == selectedBlogId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Your blogs")
            .toolbar {
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
                        Button(role: .destructive) {
                            appState.signOut()
                        } label: {
                            Label("Sign out", systemImage: "arrow.right.square")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .task { await load() }
        }
        .sheet(isPresented: Binding(
            get: { selectedBlog != nil },
            set: { if !$0 { selectedBlogId = nil } }
        )) {
            if let blog = selectedBlog {
                PostListView(blog: blog)
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let list = try await appState.api.listUserBlogs()
            blogs = list.items ?? []
            if blogs.first?.id != nil, selectedBlogId == nil {
                selectedBlogId = blogs.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
