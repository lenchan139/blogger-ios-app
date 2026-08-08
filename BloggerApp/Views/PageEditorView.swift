import SwiftUI

/// Create or edit a static page for a blog.
struct PageEditorView: View {
    let blog: Blog
    let existingPage: Page?

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var htmlBody = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(blog: Blog, page: Page?) {
        self.blog = blog
        self.existingPage = page
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Page title", text: $title, axis: .vertical)
                    .font(.title2.bold())

                if EditorSettings.useBlockEditor {
                    BlockEditorView(html: $htmlBody)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 280)
                } else {
                    RichTextEditor(html: $htmlBody)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 280)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle(existingPage == nil ? "New page" : "Edit page")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save").bold()
                    }
                }
                .disabled(isSaving)
            }
        }
        .onAppear {
            if let page = existingPage {
                title = page.title ?? ""
                htmlBody = page.content ?? ""
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let page = Page(
            kind: "blogger#page",
            id: existingPage?.id ?? "",
            blog: .init(id: blog.id),
            published: existingPage?.published,
            updated: existingPage?.updated,
            url: existingPage?.url,
            selfLink: existingPage?.selfLink,
            title: title,
            content: htmlBody,
            author: existingPage?.author
        )

        do {
            if let existing = existingPage {
                _ = try await appState.api.updatePage(page, blogId: blog.id)
            } else {
                _ = try await appState.api.insertPage(page, blogId: blog.id)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
