import SwiftUI
import UIKit
import PhotosUI
import Photos

struct PostEditorView: View {
    let blog: Blog
    let existingPost: Post?
    let openedDraft: LocalDraft?

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var htmlBody = ""
    @State private var labels: [String] = []
    @State private var draftID: String
    @State private var isSaving = false
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var imageToEdit: ImageEditPayload?
    @State private var showingSource = false
    @State private var showingPreview = false
    @State private var showingLabelsSheet = false
    @State private var errorMessage: String?
    @State private var restoredFromDraft = false
    @State private var autoSaveTask: Task<Void, Never>?

    init(blog: Blog, post: Post?, draft: LocalDraft? = nil) {
        self.blog = blog
        self.existingPost = post
        self.openedDraft = draft
        if let post {
            _draftID = State(initialValue: "post-\(post.id)")
        } else if let draft {
            _draftID = State(initialValue: draft.id)
        } else {
            _draftID = State(initialValue: "new-\(UUID().uuidString)")
        }
    }

    private var isExisting: Bool { existingPost != nil }
    private var hasLocalChanges: Bool { restoredFromDraft }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Post title", text: $title, axis: .vertical)
                .font(.title2.bold())
                .padding(.horizontal)
                .padding(.vertical, 12)

            Divider()

            if showingSource {
                TextEditor(text: $htmlBody)
                    .font(.system(.body, design: .monospaced))
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
                RichTextEditor(html: $htmlBody)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 280, maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 8) {
                LabelSummaryButton(labels: $labels) {
                    showingLabelsSheet = true
                }

                if hasLocalChanges {
                    Label("Unsaved local changes", systemImage: "externaldrive.badge.checkmark")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle(isExisting ? "Edit post" : "New post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isExisting {
                    Menu {
                        if existingPost?.status == .draft {
                            Button("Publish") { Task { await publish() } }
                        } else {
                            Button("Revert to draft") { Task { await revert() } }
                        }
                        Button("Delete post", role: .destructive) { Task { await delete() } }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                Button {
                    if isSaving { return }
                    Task { await save(isDraft: !isExisting) }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save")
                            .bold()
                    }
                }
                .disabled(isSaving)
            }
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    showingSource.toggle()
                } label: {
                    Image(systemName: showingSource ? "textformat" : "chevron.left.forwardslash.chevron.right")
                        .help(showingSource ? "Rich view" : "HTML source")
                }
                Button {
                    showingImagePicker = true
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                }
                Button {
                    showingCamera = true
                } label: {
                    Image(systemName: "camera")
                }
                Button {
                    showingPreview = true
                } label: {
                    Image(systemName: "eye")
                }
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
        .sheet(isPresented: $showingLabelsSheet) {
            NavigationStack {
                LabelsEditSheet(title: title.isEmpty ? "Untitled" : title, labels: $labels) {
                    showingLabelsSheet = false
                }
            }
        }
        .sheet(item: $imageToEdit) { payload in
            ImageEditSheet(payload: payload) { result in
                imageToEdit = nil
                Task { await insertImage(payload: payload, edit: result) }
            } onCancel: {
                imageToEdit = nil
            }
        }
        .onAppear { loadInitialContent() }
        .onChange(of: title) { _, _ in scheduleAutoSave() }
        .onChange(of: htmlBody) { _, _ in scheduleAutoSave() }
        .onChange(of: labels) { _, _ in scheduleAutoSave() }
    }

    // MARK: - Draft handling

    private func loadInitialContent() {
        // Prefer an explicitly opened draft.
        if let draft = openedDraft {
            title = draft.title
            htmlBody = draft.html
            labels = draft.labels
            restoredFromDraft = true
            return
        }

        guard existingPost != nil else {
            // Restore any prior unsaved local draft for this brand-new session.
            if let draft = appState.drafts.draft(for: draftID),
               !draft.title.isEmpty || !draft.html.isEmpty || !draft.labels.isEmpty {
                title = draft.title
                htmlBody = draft.html
                labels = draft.labels
                restoredFromDraft = true
            }
            return
        }
        // Prefer the local draft if it is newer than the remote post; otherwise use remote.
        if let draft = appState.drafts.draft(for: draftID), draft.updatedAt > (parsedRemoteUpdatedAt ?? .distantPast) {
            title = draft.title
            htmlBody = draft.html
            labels = draft.labels
            restoredFromDraft = true
        } else if let post = existingPost {
            title = post.title ?? ""
            htmlBody = post.content ?? ""
            labels = post.labels ?? []
            appState.drafts.removeForPost(blogId: blog.id, postId: post.id)
        }
    }

    private var parsedRemoteUpdatedAt: Date? {
        guard let s = existingPost?.updated else { return nil }
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
            postId: existingPost?.id,
            title: title,
            html: htmlBody,
            labels: labels,
            updatedAt: Date()
        )
        appState.drafts.upsert(draft)
        restoredFromDraft = true
    }

    // MARK: - Image insertion

    private func insertImage(payload: ImageEditPayload, edit: ImageEditResult) async {
        do {
            let url = try await appState.imageUploader.upload(imageData: edit.finalData, contentType: "image/jpeg")
            let caption = edit.caption.trimmingCharacters(in: .whitespacesAndNewlines)
            if caption.isEmpty {
                htmlBody += "\n<img src=\"\(url.absoluteString)\" alt=\"\(payload.captionEscaped ?? "")\"/>\n"
            } else {
                htmlBody += "\n<figure><img src=\"\(url.absoluteString)\" alt=\"\(caption.htmlEscaped)\"/>"
                htmlBody += "<figcaption>\(caption.htmlEscaped)</figcaption></figure>\n"
            }
        } catch {
            errorMessage = "Image upload failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Actions

    private func save(isDraft: Bool) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let post = Post(
            kind: "blogger#post",
            id: existingPost?.id ?? "",
            blog: .init(id: blog.id),
            published: existingPost?.published,
            updated: existingPost?.updated,
            url: existingPost?.url,
            selfLink: existingPost?.selfLink,
            title: title,
            content: htmlBody,
            author: existingPost?.author,
            replies: existingPost?.replies,
            status: isDraft ? .draft : (existingPost?.status ?? .live),
            labels: labels.isEmpty ? nil : labels,
            location: existingPost?.location
        )

        do {
            if let existing = existingPost {
                _ = try await appState.api.updatePost(post, blogId: blog.id)
                appState.drafts.removeForPost(blogId: blog.id, postId: existing.id)
            } else {
                let created = try await appState.api.insertPost(post, blogId: blog.id, isDraft: isDraft)
                appState.drafts.remove(id: draftID)
                appState.drafts.removeForPost(blogId: blog.id, postId: created.id)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func publish() async {
        guard let id = existingPost?.id else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await appState.api.publishPost(blogId: blog.id, postId: id)
            appState.drafts.removeForPost(blogId: blog.id, postId: id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func revert() async {
        guard let id = existingPost?.id else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await appState.api.revertPost(blogId: blog.id, postId: id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() async {
        guard let id = existingPost?.id else { return }
        do {
            try await appState.api.deletePost(blogId: blog.id, postId: id)
            appState.drafts.removeForPost(blogId: blog.id, postId: id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Image edit payload + result

struct ImageEditPayload: Identifiable {
    let id = UUID()
    let imageData: Data

    /// Value injected into the `alt` attribute when no caption is given.
    var captionEscaped: String? { nil }
}

struct ImageEditResult {
    let finalData: Data
    let caption: String
}

// MARK: - Image edit sheet (rotate + caption)

struct ImageEditSheet: View {
    let payload: ImageEditPayload
    let onConfirm: (ImageEditResult) -> Void
    let onCancel: () -> Void

    @State private var caption = ""
    @State private var rotation: Double = 0
    @State private var displayedImage: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let displayedImage {
                    Image(uiImage: displayedImage)
                        .resizable()
                        .scaledToFit()
                        .rotationEffect(.degrees(rotation))
                        .frame(maxHeight: 320)
                        .padding()
                } else {
                    ProgressView()
                }
                TextField("Caption (optional)", text: $caption, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                Spacer()
            }
            .navigationTitle("Edit image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        withAnimation { rotation += 90 }
                    } label: {
                        Image(systemName: "rotate.right")
                    }
                    Button("Insert") {
                        onConfirm(ImageEditResult(finalData: finalImageData, caption: caption))
                    }
                    .bold()
                }
            }
            .task {
                displayedImage = UIImage(data: payload.imageData)
            }
        }
    }

    private var finalImageData: Data {
        guard let image = displayedImage, rotation.truncatingRemainder(dividingBy: 360) != 0 else {
            return payload.imageData
        }
        let rotated = image.rotated(byDegrees: rotation)
        return rotated.jpegData(compressionQuality: 0.9) ?? payload.imageData
    }
}

// MARK: - UIImage rotation helper

extension UIImage {
    /// Re-renders the image rotated by the given degrees (clockwise).
    func rotated(byDegrees degrees: Double) -> UIImage {
        let radians = degrees * .pi / 180.0
        let rotatedSize = CGRect(origin: .zero, size: size)
            .applying(CGAffineTransform(rotationAngle: radians))
            .integral.size
        UIGraphicsBeginImageContextWithOptions(rotatedSize, false, scale)
        let context = UIGraphicsGetCurrentContext()
        context?.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
        context?.rotate(by: radians)
        draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage ?? self
    }
}

// MARK: - HTML escaping

extension String {
    var htmlEscaped: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - Label editor

/// Compact "Labels" row that opens a full labels editor in a sheet, keeping the
/// post body editor large.
private struct LabelSummaryButton: View {
    @Binding var labels: [String]
    var onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label("Labels", systemImage: "tag")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if labels.isEmpty {
                Text("None")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(labels, id: \.self) { label in
                            Text(label)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.tint.opacity(0.15), in: Capsule())
                                .lineLimit(1)
                        }
                    }
                }
            }
            Spacer()
            Button {
                onEdit()
            } label: {
                Text(labels.isEmpty ? "Add" : "Edit")
                    .font(.subheadline)
            }
        }
    }
}

// MARK: - Photo pickers

struct PhotoPicker: UIViewControllerRepresentable {
    var onPicked: (Data) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let controller = PHPickerViewController(configuration: config)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier("public.image") else { return }
            provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                guard let data else { return }
                DispatchQueue.main.async { self.parent.onPicked(data) }
            }
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onPicked: (Data) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.9) else { return }
            parent.onPicked(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
