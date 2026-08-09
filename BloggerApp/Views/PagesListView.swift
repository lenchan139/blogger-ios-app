import SwiftUI

/// Lists and manages the static pages of a blog, with Published/Drafts
/// filters mirroring the posts list.
struct PagesListView: View {
    let blog: Blog
    @EnvironmentObject private var appState: AppState

    enum Filter: String, CaseIterable {
        case published, drafts
        // Blogger's status query param: "live" for published, "draft" for drafts.
        var status: String {
            switch self {
            case .published: return "live"
            case .drafts: return "draft"
            }
        }
        var title: String {
            switch self {
            case .published: return "Published"
            case .drafts: return "Drafts"
            }
        }
    }

    @State private var filter: Filter = .published
    @State private var pagesByFilter: [Filter: [Page]] = [:]
    @State private var nextPageTokens: [Filter: String] = [:]
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var showNewPage = false
    @State private var editingPage: Page?

    var body: some View {
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
                    pagePage(for: blog, filter: f)
                        .tag(f)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Pages")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewPage = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showNewPage) {
            NavigationStack { PageEditorView(blog: blog, page: nil) }
        }
        .sheet(item: $editingPage) { page in
            NavigationStack { PageEditorView(blog: blog, page: page) }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func pagePage(for blog: Blog, filter: Filter) -> some View {
        let pages = pagesByFilter[filter] ?? []
        if pages.isEmpty {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No \(filter == .published ? "published" : "draft") pages",
                    systemImage: "doc.plaintext"
                )
            }
        } else {
            List {
                ForEach(pages) { page in
                    Button {
                        editingPage = page
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
                    .buttonStyle(.plain)
                }
                if hasMorePages(for: filter) {
                    loadMoreRow(for: filter)
                }
            }
            .listStyle(.plain)
            .refreshable { await load(for: filter) }
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

    private func hasMorePages(for filter: Filter) -> Bool {
        nextPageTokens[filter] != nil && !(pagesByFilter[filter]?.isEmpty ?? true)
    }

    @ViewBuilder
    private func loadMoreRow(for filter: Filter) -> some View {
        Button {
            Task { await loadMore(for: filter) }
        } label: {
            HStack {
                Spacer()
                if isLoadingMore {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.down")
                    Text("Load more")
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .foregroundStyle(.secondary)
        }
        .disabled(isLoadingMore)
        .onAppear {
            Task { await loadMore(for: filter) }
        }
    }

    private func load() async {
        for filter in Filter.allCases {
            await load(for: filter)
        }
    }

    private func load(for filter: Filter) async {
        isLoading = true
        errorMessage = nil
        do {
            let list = try await appState.api.listPages(blogId: blog.id, status: filter.status)
            pagesByFilter[filter] = list.items ?? []
            nextPageTokens[filter] = list.nextPageToken
        } catch {
            if Task.isCancelled { return }
            if let urlErr = error as? URLError, urlErr.code == .cancelled { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMore(for filter: Filter) async {
        guard let token = nextPageTokens[filter], !token.isEmpty else { return }
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let list = try await appState.api.listPages(blogId: blog.id, status: filter.status, pageToken: token)
            var all = pagesByFilter[filter] ?? []
            let existingIDs = Set(all.map(\.id))
            all.append(contentsOf: (list.items ?? []).filter { !existingIDs.contains($0.id) })
            pagesByFilter[filter] = all
            nextPageTokens[filter] = list.nextPageToken
        } catch {
            if Task.isCancelled { return }
            if let urlErr = error as? URLError, urlErr.code == .cancelled { return }
            errorMessage = error.localizedDescription
        }
    }

    private static func relative(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return "" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
