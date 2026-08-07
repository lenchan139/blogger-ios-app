import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.isSignedIn {
                BlogSwitcherView()
            } else {
                SignInView()
            }
        }
        .animation(.easeInOut, value: appState.isSignedIn)
    }
}
