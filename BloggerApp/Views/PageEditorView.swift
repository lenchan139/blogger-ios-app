import SwiftUI
import UIKit
import PhotosUI
import Photos

/// Create or edit a static page for a blog. Mirrors PostEditorView's editing
/// capabilities (source toggle, preview, image insertion, local drafts),
/// minus labels — Blogger pages don't support labels.
struct PageEditorView: View {
    let blog: Blog
    let existingPage: Page?

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var htmlBody = ""
    @State private var draftID: String
    @State private var isSaving = false
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var imageToEdit: ImageEditPayload?
    @State private var showingSource = false
    @State private var showingPreview = false
    @State private var errorMessage: String?
    @State private var alertMessage: String?
    @State private var isUploading = false
    @State private var restoredFromDraft = false
    @State private var autoSaveTask: Task<Void, Never>?
    @StateObject private var richEditorRef = RichEditorRef()

    init(blog: Blog, page: Page?) {
        self.blog = blog
        self.existingPage = page
        if let page {
            _draftID = State(initialValue: "page-\(page.id)")
        } else {
            _draftID = State(initialValue: "new-page-\(UUID().uuidString)")
        }
    }

    private var isExisting: Bool { existingPage != nil }
    private var hasLocalChanges: Bool { restoredFromDraft }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if hasLocalChanges {
                    Label("Unsaved local changes", systemImage: "externaldrive.badge.checkmark")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                TextField("Page title", text: $title, axis: .vertical)
                    .font(.title2.bold())

                if showingSource {
                    TextEditor(text: $htmlBody)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 280)
                        .overlay(alignment: .topLeading) {
                            if htmlBody.isEmpty {
                                Text("HTML source")
                                    .foregroundStyle(.secondary)
                                    .allowsHitTesting(false)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                        }
                        .padding(6)
                        .background(Color(.secondarySystemBackground))
                } else {
                    RichEditorView(html: $htmlBody, editorRef: richEditorRef) {
                        showingImagePicker = true
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 320)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle(isExisting ? "Edit page" : "New page")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .disabled(isSaving || isUploading)
            }
            ToolbarItemGroup(placement: .principal) {
                Button {
                    showingSource.toggle()
                } label: {
                    Image(systemName: showingSource ? "textformat" : "chevron.left.forwardslash.chevron.right")
                        .help(showingSource ? "Rich view" : "HTML source")
                }
                Button {
                    showingPreview = true
                } label: {
                    Image(systemName: "eye")
                }
                if isExisting {
                    Menu {
                        Button("Delete page", role: .destructive) { Task { await delete() } }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if isSaving { return }
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .bold()
                    }
                }
                .disabled(isSaving)
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            PhotoPicker(onPicked: { data in
                imageToEdit = ImageEditPayload(imageData: data)
            })
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(onPicked: { data in
                imageToEdit = ImageEditPayload(imageData: data)
            })
        }
        .sheet(isPresented: $showingPreview) {
            ThemedPreviewView(blog: blog, html: htmlBody)
        }
        .sheet(item: $imageToEdit) { payload in
            ImageEditSheet(payload: payload) { result in
                imageToEdit = nil
                Task { await insertImage(payload: payload, edit: result) }
            } onCancel: {
                imageToEdit = nil
            }
        }
        .alert("Upload failed", isPresented: .init(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .overlay {
            if isUploading {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Uploading image…")
                            .font(.headline)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding()
                }
            }
        }
        .onAppear { loadInitialContent() }
        .onChange(of: title) { _, _ in scheduleAutoSave() }
        .onChange(of: htmlBody) { _, _ in scheduleAutoSave() }
    }

    // MARK: - Draft handling

    private func loadInitialContent() {
        guard existingPage != nil else {
            // Restore any prior unsaved local draft for this brand-new page.
            if let draft = appState.drafts.draft(for: draftID),
               !draft.title.isEmpty || !draft.html.isEmpty {
                title = draft.title
                htmlBody = draft.html
                restoredFromDraft = true
            }
            return
        }
        // Prefer the local draft if it is newer than the remote page; otherwise use remote.
        if let draft = appState.drafts.draft(for: draftID), draft.updatedAt > (parsedRemoteUpdatedAt ?? .distantPast) {
            title = draft.title
            htmlBody = draft.html
            restoredFromDraft = true
        } else if let page = existingPage {
            title = page.title ?? ""
            htmlBody = page.content ?? ""
            appState.drafts.removeForPost(blogId: blog.id, postId: page.id)
        }
    }

    private var parsedRemoteUpdatedAt: Date? {
        guard let s = existingPage?.updated else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await self.autoSave()
        }
    }

    private func autoSave() {
        let draft = LocalDraft(
            id: draftID,
            blogId: blog.id,
            postId: existingPage?.id,
            title: title,
            html: htmlBody,
            labels: [],
            updatedAt: Date()
        )
        appState.drafts.upsert(draft)
        restoredFromDraft = true
    }

    // MARK: - Image insertion

    /// Inserts a placeholder image in the editor, shows an uploading spinner,
    /// then swaps the placeholder for the real URL on success or removes it
    /// if the upload fails.
    private func insertImage(payload: ImageEditPayload, edit: ImageEditResult) async {
        let placeholderID = UUID().uuidString
        let placeholderURL = "blogger-upload://pending-\(placeholderID)"
        let caption = edit.caption.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Reserve the spot in the editor with a unique placeholder src.
        richEditorRef.insertImage(url: placeholderURL, caption: caption)
        isUploading = true
        await waitForPlaceholder(placeholderURL)

        do {
            let url = try await appState.imageUploader.upload(imageData: edit.finalData, contentType: "image/jpeg")
            // 2. Success: swap the placeholder src for the real URL.
            htmlBody = htmlBody.replacingOccurrences(of: placeholderURL, with: url.absoluteString)
            richEditorRef.setHTML(htmlBody)
        } catch {
            // 3. Failure: remove the placeholder <img> from the document.
            print("[ImageUpload] failed: \(String(describing: error))")
            let pattern = "<img[^>]*blogger-upload://pending-\(placeholderID)[^>]*>"
            htmlBody = htmlBody.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            richEditorRef.setHTML(htmlBody)
            alertMessage = "Image upload failed: \(String(describing: error))"
        }

        isUploading = false
    }

    /// The editor reports its HTML back asynchronously via the JS bridge;
    /// wait (briefly) until our placeholder shows up so replace/remove
    /// operations have something to find.
    private func waitForPlaceholder(_ placeholderURL: String) async {
        let deadline = Date().addingTimeInterval(1.0)
        while !htmlBody.contains(placeholderURL) && Date() < deadline {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    // MARK: - Actions

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
                appState.drafts.removeForPost(blogId: blog.id, postId: existing.id)
            } else {
                _ = try await appState.api.insertPage(page, blogId: blog.id)
                appState.drafts.remove(id: draftID)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() async {
        guard let id = existingPage?.id else { return }
        do {
            try await appState.api.deletePage(blogId: blog.id, pageId: id)
            appState.drafts.removeForPost(blogId: blog.id, postId: id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
