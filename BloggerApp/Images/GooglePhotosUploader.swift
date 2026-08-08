import Foundation
import GoogleSignIn

/// Uploads images to the user's Google Photos library via the
/// `photoslibrary.appendonly` scope, then returns the shareable URL.
/// Blogger stores posts as HTML, so we embed the returned `<img>` URL.
struct GooglePhotosUploader: ImageUploading {
    private static let baseURL = URL(string: "https://photoslibrary.googleapis.com/v1")!

    func upload(imageData: Data, contentType: String) async throws -> URL {
        let token = try await AuthManager.shared.currentAccessToken()
        let tokenValue = token

        // Step 1: initialize an upload session to get an upload token.
        let uploadToken = try await startUpload(data: imageData, contentType: contentType, token: tokenValue)

        // Step 2: create a media item referencing the upload token.
        let baseURL = try await createMediaItem(uploadToken: uploadToken, token: tokenValue)
        return baseURL
    }

    private func startUpload(data: Data, contentType: String, token: String) async throws -> String {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("uploads"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("X-Goog-Upload-Command: start, upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        request.setValue("X-Goog-Upload-Header-Content-Type: \(contentType)", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        request.setValue("X-Goog-Upload-Protocol: raw", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        request.setValue("\(data.count)", forHTTPHeaderField: "X-Goog-Upload-Content-Length")
        request.httpBody = data

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: responseData, encoding: .utf8) ?? ""
            throw BloggerError.http(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1,
                message: "Photo upload failed: \(body.prefix(200))"
            )
        }
        guard let uploadToken = String(data: responseData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !uploadToken.isEmpty else {
            throw BloggerError.emptyResponse
        }
        return uploadToken
    }

    private func createMediaItem(uploadToken: String, token: String) async throws -> URL {
        struct Body: Encodable {
            let newMediaItems: [NewMediaItem]
            struct NewMediaItem: Encodable {
                let simpleMediaItem: SimpleMediaItem
                struct SimpleMediaItem: Encodable {
                    let uploadToken: String
                }
            }
        }
        // `mediaItem` is optional: Google returns item-level errors as a
        // `status` object without a `mediaItem` key, even on HTTP 200.
        struct Response: Decodable {
            struct MediaItem: Decodable {
                let baseUrl: String
                let productUrl: String
            }
            struct ItemStatus: Decodable {
                let code: Int?
                let message: String?
            }
            struct MediaItemResult: Decodable {
                let mediaItem: MediaItem?
                let status: ItemStatus?
            }
            let newMediaItemResults: [MediaItemResult]?
        }

        var request = URLRequest(url: Self.baseURL.appendingPathComponent("mediaItems:batchCreate"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(newMediaItems: [.init(simpleMediaItem: .init(uploadToken: uploadToken))]))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BloggerError.http(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1, message: "Photo record creation failed")
        }

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            // Not the expected shape: surface the raw Google error payload.
            let raw = String(data: data, encoding: .utf8) ?? "empty"
            throw BloggerError.http(statusCode: http.statusCode, message: "Unexpected response: \(raw.prefix(300))")
        }

        if let first = decoded.newMediaItemResults?.first {
            if let mediaItem = first.mediaItem {
                return URL(string: mediaItem.baseUrl)!
            }
            if let status = first.status, let message = status.message {
                throw BloggerError.http(statusCode: status.code ?? -1, message: "Photo record creation failed: \(message)")
            }
        }
        throw BloggerError.emptyResponse
    }
}
