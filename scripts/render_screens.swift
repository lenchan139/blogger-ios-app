// render_screens.swift — generate app screenshots with Swift only
//
// Renders mock versions of the app's screens with SwiftUI ImageRenderer and
// writes PNGs sized like an iPhone screen (1179x2556 @3x => 393x852 pt).
//
// Build & run:
//   swiftc -parse-as-library render_screens.swift -o render_screens
//   ./render_screens <output-dir>

import SwiftUI
import AppKit
import CoreGraphics

let ACCENT = Color(red: 0xF5 / 255, green: 0x7C / 255, blue: 0x03 / 255)
let W: CGFloat = 393
let H: CGFloat = 852

// MARK: - Mock data

struct MockPost: Identifiable {
    let id = UUID()
    let title: String
    let date: String
    let status: Status
    enum Status { case published, draft }
}

let mockPosts: [MockPost] = [
    .init(title: "My first post with BloggerApp", date: "2 hours ago", status: .published),
    .init(title: "A guide to writing on the go", date: "Yesterday", status: .published),
    .init(title: "Draft: camping trip photos", date: "3 days ago", status: .draft),
    .init(title: "SwiftUI tips for bloggers", date: "Last week", status: .published),
    .init(title: "Draft: ideas for next month", date: "Last week", status: .draft),
]

// MARK: - Screens

struct SignInScreen: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "pencil.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(ACCENT)
            Text("Blogger")
                .font(.largeTitle.bold())
            Text("Write, edit and publish posts on the go.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Label("Sign in with Google", systemImage: "g.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(ACCENT, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
                .padding(.horizontal)
        }
        .padding(.bottom, 32)
    }
}

struct PostListScreen: View {
    @State private var filter = 0
    var body: some View {
        VStack(spacing: 0) {
            // Nav bar
            HStack {
                Image(systemName: "line.3.horizontal")
                Spacer()
                Text("Posts").font(.headline)
                Spacer()
                Image(systemName: "person.crop.circle.fill")
            }
            .padding(.horizontal).padding(.vertical, 10)

            // Segmented filter
            HStack(spacing: 0) {
                ForEach(["Published", "Drafts", "Local"], id: \.self) { name in
                    Text(name)
                        .font(.subheadline.weight(filter == 0 ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(filter == 0 ? ACCENT : Color.clear)
                        .foregroundStyle(filter == 0 ? .white : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(4)
            .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal).padding(.vertical, 8)

            List {
                ForEach(mockPosts) { post in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(post.title).font(.headline)
                        HStack(spacing: 8) {
                            if post.status == .draft {
                                Text("Draft")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(ACCENT.opacity(0.15), in: Capsule())
                                    .foregroundStyle(ACCENT)
                            }
                            Text(post.date).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)

            Spacer()
        }
        .frame(width: W, height: H)
    }
}

struct EditorScreen: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Nav bar
            HStack {
                Image(systemName: "xmark")
                Spacer()
                Text("New post").font(.headline)
                Spacer()
                Text("Save").font(.headline).foregroundStyle(ACCENT)
            }
            .padding(.horizontal).padding(.vertical, 10)

            TextField("Post title", text: .constant(""))
                .font(.title2.bold())
                .padding(.horizontal)

            // Formatting toolbar (mock)
            HStack(spacing: 16) {
                ForEach(["B", "I", "U", "S", "•", "1.", "≡", "\""], id: \.self) { s in
                    Text(s)
                        .font(s.count > 1 ? .body.bold() : .headline.bold())
                        .frame(width: 26, height: 26)
                        .foregroundStyle(s == "B" || s == "I" ? ACCENT : .primary)
                }
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)

            // Editor body placeholder
            VStack(alignment: .leading, spacing: 8) {
                Text("Write your post…")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                Rectangle()
                    .fill(Color.gray.opacity(0.08))
                    .frame(height: 140)
                    .overlay(alignment: .topLeading) {
                        Text("A demo of the rich text editor…")
                            .padding(12)
                            .foregroundStyle(.tertiary)
                    }
            }
            .padding(.horizontal)

            Spacer()
        }
        .frame(width: W, height: H)
    }
}

// MARK: - Renderer

@main
struct Main {
    @MainActor
    static func main() throws {
        let outDir = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : FileManager.default.currentDirectoryPath + "/screenshots"
        try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        let screens: [(String, AnyView)] = [
            ("signin", AnyView(SignInScreen())),
            ("posts", AnyView(PostListScreen())),
            ("editor", AnyView(EditorScreen())),
        ]

        for (name, view) in screens {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            renderer.proposedSize = ProposedViewSize(width: W, height: H)
            renderer.isOpaque = true
            guard let cg = renderer.cgImage else {
                print("failed to render \(name)")
                continue
            }
            let rep = NSBitmapImageRep(cgImage: cg)
            guard let png = rep.representation(using: .png, properties: [:]) else { continue }
            let url = URL(fileURLWithPath: "\(outDir)/\(name).png")
            try png.write(to: url)
            print("saved: \(url.path)")
        }
    }
}
