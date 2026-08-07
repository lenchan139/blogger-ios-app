import Foundation

enum Configuration {
    // MARK: - OAuth 2.0

    /// The OAuth 2.0 Client ID for this iOS app from the Google Cloud Console.
    /// IMPORTANT: Replace this with your own client ID. Keep it in a config file
    /// that is NOT committed to source control in production.
    static let googleClientID = "REPLACE_WITH_YOUR_CLIENT_ID"

    /// Reverse-DNS scheme used by GoogleSignIn to return to this app, e.g.
    /// "com.googleusercontent.apps.<client-id-with-dashes>" is the default.
    static let googleURLScheme = "com.googleusercontent.apps.REPLACE_ME"

    /// OAuth scopes requested from the user.
    static let scopes: [String] = [
        "https://www.googleapis.com/auth/blogger",
        "https://www.googleapis.com/auth/photoslibrary.appendonly"
    ]
}
