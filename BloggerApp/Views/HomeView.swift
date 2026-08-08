import SwiftUI

/// The main screen: hosts Posts / Comments / Blog info sections with a bottom
/// dock, plus a context-aware compose button.
struct HomeView: View {
    @EnvironmentObject private var appState: AppState

    enum Section {
        case posts, comments, blogInfo
    }
    enum BlogInfoTab {
        case info, stats, pages
    }

    @State private var section: Section = .posts
    @State private var blogInfoTab: BlogInfoTab = .info
    @State private var blogs: [Blog] = []
    @State private var selectedBlogId: String?

    private var selectedBlog: Blog? {
        blogs.first { $0.id == selectedBlogId } ?? blogs.first
    }

    var body: some View {
        TabView(selection: $section) {
            PostListView(blogs: blogs, selectedBlogId: $selectedBlogId)
                .tabItem { Label("Posts", systemImage: "doc.text") }
                .tag(Section.posts)

            NavigationStack {
                if let blog = selectedBlog {
                    AllCommentsView(blog: blog)
                } else {
                    ContentUnavailableView("No blog", systemImage: "doc.text")
                }
            }
            .tabItem { Label("Comments", systemImage: "text.bubble") }
            .tag(Section.comments)

            BlogInfoTabs(blog: selectedBlog, tab: $blogInfoTab)
                .tabItem { Label("Blog info", systemImage: "info.circle") }
                .tag(Section.blogInfo)
        }
        .task { await loadBlogs() }
    }

    private func loadBlogs() async {
        do {
            let list = try await appState.api.listUserBlogs()
            blogs = list.items ?? []
            if selectedBlogId == nil {
                selectedBlogId = blogs.first?.id
            }
        } catch {
            // Sections will show empty states.
        }
    }
}

/// Blog info section: switches between Blog info / Stats / Pages via a tab bar.
struct BlogInfoTabs: View {
    let blog: Blog?
    @Binding var tab: HomeView.BlogInfoTab

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $tab) {
                    Text("Blog info").tag(HomeView.BlogInfoTab.info)
                    Text("Stats").tag(HomeView.BlogInfoTab.stats)
                    Text("Pages").tag(HomeView.BlogInfoTab.pages)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Group {
                    if let blog {
                        switch tab {
                        case .info: BlogInfoView(blog: blog)
                        case .stats: StatsView(blog: blog)
                        case .pages: PagesListView(blog: blog)
                        }
                    } else {
                        ContentUnavailableView("No blog", systemImage: "doc.text")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
