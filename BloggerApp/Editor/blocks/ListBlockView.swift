import SwiftUI

struct ListBlockView: View {
    let ordered: Bool
    @Binding var content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: ordered ? "list.number" : "list.bullet")
                    .font(.caption)
                Text("One item per line")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            GrowingTextEditor(text: $content, font: .preferredFont(forTextStyle: .body))
        }
    }
}