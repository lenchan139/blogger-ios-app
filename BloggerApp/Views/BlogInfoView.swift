import SwiftUI

/// Displays blog details and the authenticated user's access role for a blog.
/// Note: the Blogger API v3 does not expose an endpoint to update blog
/// metadata (name/description/etc.), so this screen is read-only.
struct BlogInfoView: View {
    let blog: Blog
    @EnvironmentObject private var appState: AppState

    @State private var userInfo: BlogUserInfo?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var role: String? {
        userInfo?.blog_user_info?.role
    }

    var body: some View {
        Form {
            Section("Blog") {
                LabeledContent("Name", value: blog.name ?? "Untitled")
                if let description = blog.description, !description.isEmpty {
                    LabeledContent("Description", value: description)
                }
                if let url = blog.url {
                    LabeledContent("URL") {
                        Link(url, destination: URL(string: url)!)
                    }
                }
                if let published = blog.published {
                    LabeledContent("Published", value: Self.date(published))
                }
                if let updated = blog.updated {
                    LabeledContent("Last updated", value: Self.date(updated))
                }
            }

            Section("Content") {
                LabeledContent("Posts", value: "\(blog.posts?.totalItems ?? 0)")
                LabeledContent("Pages", value: "\(blog.pages?.totalItems ?? 0)")
            }

            Section {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading role…")
                            .foregroundStyle(.secondary)
                    }
                } else if let role {
                    LabeledContent("Role", value: role.capitalized)
                } else {
                    Text("Not available")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Your access")
            } footer: {
                Text("The public Blogger API cannot change blog settings (name, description, layout). Use blogger.com to edit these.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Blog info")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadUserInfo() }
    }

    private func loadUserInfo() async {
        isLoading = true
        errorMessage = nil
        do {
            userInfo = try await appState.api.getBlogUserInfo(blog.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private static func date(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
