import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.isSignedIn {
                HomeView()
            } else {
                SignInView()
            }
        }
        .animation(.easeInOut, value: appState.isSignedIn)
    }
}
