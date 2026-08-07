import SwiftUI

@main
struct BloggerApp: App {
    @StateObject private var appState = AppState()

    init() {
        // Configure Google Sign-In to return to this app via the URL scheme.
        AuthManager.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .onOpenURL { url in
                    AuthManager.shared.handle(url: url)
                }
        }
    }
}
