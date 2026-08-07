import Foundation
import GoogleSignIn
import SwiftUI

/// Wraps Google Sign-In and exposes the Blogger OAuth token to the API client.
/// Conforms to `AccessTokenProvider` so `BloggerClient` can authorize requests.
final class AuthManager: AccessTokenProvider, ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var currentUser: GIDGoogleUser?

    private init() {
        self.currentUser = GIDSignIn.sharedInstance.currentUser
    }

    /// Must be called once from `App.init`.
    static func configure() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: Configuration.googleClientID)
    }

    /// Restores a previously signed-in user from the keychain. On a fresh
    /// launch `currentUser` is nil even if the user was signed in before, so we
    /// must call this to reload the persisted session.
    func restorePreviousSignIn() async {
        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else { return }
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            currentUser = user
        } catch {
            currentUser = nil
        }
    }

    var isSignedIn: Bool { currentUser != nil }

    /// Call from `onOpenURL`.
    func handle(url: URL) {
        GIDSignIn.sharedInstance.handle(url)
    }

    /// Presents the native Google sign-in flow. Call from a view controller.
    func signIn() async throws {
        guard let rootVC = Self.topViewController() else {
            throw BloggerError.http(statusCode: -1, message: "No view controller to present sign-in.")
        }
        let user: GIDGoogleUser = try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: rootVC,
                hint: nil,
                additionalScopes: Configuration.scopes
            ) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let user = result?.user {
                    continuation.resume(returning: user)
                } else {
                    continuation.resume(throwing: BloggerError.http(statusCode: -1, message: "Sign-in returned no user."))
                }
            }
        }
        currentUser = user
        let refreshToken = user.refreshToken.tokenString
        if !refreshToken.isEmpty {
            KeychainTokenStore.save(refreshToken)
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        currentUser = nil
        KeychainTokenStore.clear()
    }

    /// Current access token for authorized API calls. Refreshes if needed.
    func currentAccessToken() async throws -> String {
        guard let user = currentUser else {
            throw BloggerError.noAccessToken
        }
        do {
            try await user.refreshTokensIfNeeded()
        } catch {
            throw BloggerError.http(statusCode: -1, message: "Could not refresh the session. Please sign in again.")
        }
        let token = user.accessToken.tokenString
        guard !token.isEmpty else {
            throw BloggerError.noAccessToken
        }
        return token
    }

    private static func topViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
