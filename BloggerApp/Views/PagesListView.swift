import SwiftUI

/// Lists and manages the static pages of a blog.
struct PagesListView: View {
    let blog: Blog
    @EnvironmentObject private var appState: AppState

    @State private var pages: [Page] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading pages…")
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Couldn't load pages", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
            } else if pages.isEmpty {
                ContentUnavailableView("No pages yet", systemImage: "doc.plaintext")
            } else {
                List {
                    ForEach(pages) { page in
                        NavigationLink {
                            PageEditorView(blog: blog, page: page)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(page.title?.isEmpty == false ? page.title! : "Untitled")
                                    .font(.headline)
                                if let updated = page.updated {
                                    Text("Updated \(Self.relative(updated))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete(perform: delete)
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle("Pages")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    PageEditorView(blog: blog, page: nil)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let list = try await appState.api.listPages(blogId: blog.id)
            pages = list.items ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func delete(at offsets: IndexSet) {
        let ids = offsets.map { pages[$0].id }
        Task {
            for id in ids {
                try? await appState.api.deletePage(blogId: blog.id, pageId: id)
            }
            await load()
        }
    }

    private static func relative(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return "" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
