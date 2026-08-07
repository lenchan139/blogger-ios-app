import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "pencil.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.tint)
            Text("Blogger")
                .font(.largeTitle.bold())
            Text("Write, edit and publish posts on the go.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button {
                Task { await appState.signIn() }
            } label: {
                Label("Sign in with Google", systemImage: "g.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.tint, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal)
        }
    }
}
