import Foundation

enum Configuration {
    // MARK: - OAuth 2.0

    /// The OAuth 2.0 Client ID for this iOS app from the Google Cloud Console.
    /// IMPORTANT: Replace this with your own client ID. Keep it in a config file
    /// that is NOT committed to source control in production.
    ///
    /// How to get it:
    ///   1. Go to https://console.cloud.google.com/apis/credentials
    ///   2. Enable the "Blogger API" and "Photos Library API" for your project.
    ///   3. Click "Create credentials" > "OAuth client ID" > "iOS".
    ///   4. Set the bundle ID to match this app (e.g. com.lenchan139.bloggerios).
    ///   5. Copy the generated "Client ID" value here, and use its associated
    ///      URL scheme (com.googleusercontent.apps.<client-id-with-dashes>)
    ///      for `googleURLScheme` below.
    static let googleClientID = "579169224720-9locuddld8dupm50oc197o0cg165tq90.apps.googleusercontent.com"

    /// Reverse-DNS scheme used by GoogleSignIn to return to this app.
    /// Derived automatically from `googleClientID`: "com.googleusercontent.apps."
    /// + the client ID with the ".apps.googleusercontent.com" suffix stripped and
    /// any remaining "." replaced by "-".
    /// e.g. client ID "1234-x.apps.googleusercontent.com" ->
    ///      scheme  "com.googleusercontent.apps.1234-x"
    static var googleURLScheme: String {
        let stripped = googleClientID
            .replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps." + stripped.replacingOccurrences(of: ".", with: "-")
    }

    /// OAuth scopes requested from the user.
    ///
    /// `drive.file` gives access only to files *created by this app* — used
    /// to upload user-selected images to the user's Drive, make them public,
    /// and embed the permanent URL in blog post HTML. (Google Photos base
    /// URLs expire after 60 minutes, so Drive is used as the image host.)
    static let scopes: [String] = [
        "https://www.googleapis.com/auth/blogger",
        "https://www.googleapis.com/auth/drive.file"
    ]
}
