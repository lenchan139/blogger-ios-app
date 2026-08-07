import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var isSignedIn = false
    @Published var userEmail: String?

    let api = BloggerClient()
    let imageUploader: ImageUploading = GooglePhotosUploader()
    let drafts = LocalDraftStore()

    init() {
        isSignedIn = AuthManager.shared.isSignedIn
    }

    func signIn() async {
        do {
            try await AuthManager.shared.signIn()
            isSignedIn = true
            userEmail = AuthManager.shared.currentUser?.profile?.email
        } catch {
            isSignedIn = false
        }
    }

    func signOut() {
        AuthManager.shared.signOut()
        isSignedIn = false
        userEmail = nil
    }
}
