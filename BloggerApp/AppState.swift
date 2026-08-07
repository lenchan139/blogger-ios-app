import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var isSignedIn = false
    @Published var userEmail: String?
    @Published var userAvatarURL: URL?

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
            updateUserProfile()
        } catch {
            isSignedIn = false
        }
    }

    /// Reads the signed-in user's email and avatar URL from the auth session.
    private func updateUserProfile() {
        let profile = AuthManager.shared.currentUser?.profile
        userEmail = profile?.email
        userAvatarURL = profile?.imageURL(withDimension: 96)
    }

    func signOut() {
        AuthManager.shared.signOut()
        isSignedIn = false
        userEmail = nil
        userAvatarURL = nil
    }

    /// Signs out the current Google account and immediately presents the
    /// sign-in flow again so the user can pick a different account.
    func switchAccount() async {
        AuthManager.shared.signOut()
        isSignedIn = false
        userEmail = nil
        userAvatarURL = nil
        await signIn()
    }
}
