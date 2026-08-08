import SwiftUI

struct ImageBlockView: View {
    @Binding var block: Block

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if block.attributes["uploadState"] == "uploading" {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Uploading image…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if let url = URL(string: block.content), !block.content.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(height: 200)
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        failedView
                    @unknown default:
                        failedView
                    }
                }
            } else {
                placeholderView
            }

            if let caption = block.attributes["caption"], !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var placeholderView: some View {
        HStack {
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No image")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var failedView: some View {
        failedImage
            .resizable()
            .scaledToFit()
            .frame(height: 200)
    }

    private var failedImage: Image {
        Image(systemName: "photo.badge.exclamationmark")
    }
}