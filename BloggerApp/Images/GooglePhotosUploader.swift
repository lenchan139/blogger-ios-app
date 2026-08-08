import Foundation
import GoogleSignIn

/// Uploads images to the user's Google Photos library and returns a
/// `baseUrl` (lh3.googleusercontent.com) suitable for embedding in post HTML.
///
/// Implements the two-step flow documented at:
///   https://developers.google.com/photos/library/guides/upload-media
///   https://developers.google.com/photos/library/guides/access-media-items
///
/// Step 1 — `/v1/uploads` (`photoslibrary.appendonly`):
///   POST the raw media bytes; the response body is an opaque upload token.
///   Headers per docs: `Content-type: application/octet-stream`,
///   `X-Goog-Upload-Content-Type: <mime>`, `X-Goog-Upload-Protocol: raw`.
///
/// Step 2 — `/v1/mediaItems:batchCreate` (`photoslibrary.appendonly`):
///   POST JSON referencing the upload token. The response's `mediaItem`
///   contains `id`, `productUrl`, `mimeType`, `mediaMetadata`, `filename`
///   — but NOT `baseUrl` (per the docs' sample response).
///
/// Step 3 — `GET /v1/mediaItems/{id}`
///   (`photoslibrary.readonly.appcreateddata`):
///   Returns the full `MediaItem` including `baseUrl`, the only URL that
///   serves raw image bytes for an `<img>`. A size suffix (e.g. `=w1024-h1024`)
///   MUST be appended before use, as documented. The `baseUrl` expires after
///   60 minutes — callers embedding it in long-lived content must be aware.
struct GooglePhotosUploader: ImageUploading {
    private static let baseURL = URL(string: "https://photoslibrary.googleapis.com/v1")!
    private static var transport: UploadTransport { .shared }

    func upload(imageData: Data, contentType: String) async throws -> URL {
        let token = try await AuthManager.shared.currentAccessToken()
        let uploadToken = try await uploadBytes(imageData, contentType: contentType, token: token)
        let mediaItemId = try await createMediaItem(uploadToken: uploadToken, token: token)
        let baseUrl = try await resolveBaseUrl(mediaItemId: mediaItemId, token: token)
        return baseUrl
    }
}

// MARK: - Step 1: Upload bytes

private extension GooglePhotosUploader {
    /// POST raw bytes to `/v1/uploads`; returns the opaque upload token.
    func uploadBytes(_ data: Data, contentType: String, token: String) async throws -> String {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("uploads"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Headers per official docs.
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-type")
        request.setValue(contentType, forHTTPHeaderField: "X-Goog-Upload-Content-Type")
        request.setValue("raw", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        request.httpBody = data

        let (body, response) = try await Self.transport.send(request)
        guard let http = response, http.statusCode == 200 else {
            throw BloggerError.http(statusCode: response?.statusCode ?? -1,
                                    message: Self.errorText(body))
        }
        let uploadToken = String(data: body, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !uploadToken.isEmpty else {
            throw BloggerError.emptyResponse
        }
        return uploadToken
    }
}

// MARK: - Step 2: Create media item

private extension GooglePhotosUploader {
    private struct BatchCreateBody: Encodable {
        let newMediaItems: [NewItem]
        struct NewItem: Encodable {
            let description: String?
            let simpleMediaItem: Simple
            struct Simple: Encodable {
                let fileName: String
                let uploadToken: String
            }
        }
    }
    private struct BatchCreateResponse: Decodable {
        let newMediaItemResults: [Result]?
        struct Result: Decodable {
            let uploadToken: String?
            let status: Status?
            let mediaItem: MediaItem?
        }
        struct Status: Decodable {
            let code: Int?
            let message: String?
        }
        struct MediaItem: Decodable {
            let id: String?
            let productUrl: String?
            let mimeType: String?
            let filename: String?
        }
    }

    /// Calls `batchCreate` with the upload token; returns the new media
    /// item's stable `id`. Per docs, `baseUrl` is NOT in this response —
    /// it must be fetched separately via `mediaItems.get`.
    func createMediaItem(uploadToken: String, token: String) async throws -> String {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("mediaItems:batchCreate"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-type")
        request.httpBody = try JSONEncoder().encode(BatchCreateBody(newMediaItems: [
            .init(description: nil,
                  simpleMediaItem: .init(fileName: "image.jpg", uploadToken: uploadToken))
        ]))

        let (body, response) = try await Self.transport.send(request)

        // The docs note: 200 if all items succeed; 207 if some fail.
        guard let http = response, http.statusCode == 200 || http.statusCode == 207 else {
            throw BloggerError.http(statusCode: response?.statusCode ?? -1,
                                    message: Self.errorText(body))
        }

        let decoded: BatchCreateResponse
        do {
            decoded = try JSONDecoder().decode(BatchCreateResponse.self, from: body)
        } catch {
            let raw = String(data: body, encoding: .utf8) ?? "<binary>"
            NSLog("[GooglePhotos] batchCreate decode failed: \(raw.prefix(800))")
            throw BloggerError.http(statusCode: http.statusCode,
                                    message: "Bad response: \(raw.prefix(500))")
        }

        guard let first = decoded.newMediaItemResults?.first else {
            throw BloggerError.emptyResponse
        }
        // Per docs: a non-zero status code indicates an error for that item.
        if let status = first.status, let code = status.code, code != 0 {
            throw BloggerError.http(statusCode: code, message: status.message ?? "Item creation failed")
        }
        guard let id = first.mediaItem?.id, !id.isEmpty else {
            throw BloggerError.emptyResponse
        }
        return id
    }
}

// MARK: - Step 3: Resolve baseUrl

private extension GooglePhotosUploader {
    private struct MediaItemResponse: Decodable {
        let id: String?
        let baseUrl: String?
        let mimeType: String?
    }

    /// Fetches `GET /v1/mediaItems/{id}` until `baseUrl` is present. Per docs,
    /// this requires `photoslibrary.readonly.appcreateddata`. Photos return
    /// `baseUrl` immediately; videos return it after processing completes.
    func resolveBaseUrl(mediaItemId: String, token: String) async throws -> URL {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("mediaItems/\(mediaItemId)"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-type")

        // Retry briefly to allow server-side processing. Per docs, photos are
        // typically immediately available, but we wait a few cycles in case.
        let delays: [UInt64] = [0, 1_000_000_000, 2_000_000_000, 4_000_000_000]
        for (idx, nap) in delays.enumerated() {
            if nap > 0 { try? await Task.sleep(nanoseconds: nap) }
            let (body, response) = try await Self.transport.send(request)
            guard let http = response else { continue }

            // Insufficient scopes — caller must re-auth to grant the new scope.
            if http.statusCode == 403 {
                let raw = String(data: body, encoding: .utf8) ?? ""
                NSLog("[GooglePhotos] mediaItems.get 403 (attempt \(idx)): \(raw.prefix(400))")
                if raw.contains("ACCESS_TOKEN_SCOPE_INSUFFICIENT")
                    || raw.contains("PERMISSION_DENIED") {
                    throw ImageUploadError.requiresReauthentication
                }
                continue
            }
            guard http.statusCode == 200 else { continue }

            guard let item = try? JSONDecoder().decode(MediaItemResponse.self, from: body) else {
                let raw = String(data: body, encoding: .utf8) ?? "<binary>"
                NSLog("[GooglePhotos] mediaItems.get decode failed: \(raw.prefix(400))")
                continue
            }
            if let base = item.baseUrl, !base.isEmpty {
                return Self.imageUrl(base)
            }
        }
        NSLog("[GooglePhotos] baseUrl never appeared for \(mediaItemId)")
        throw BloggerError.emptyResponse
    }

    /// Appends a Blogger-friendly size suffix per docs:
    /// `=w1024-h1024` caps the longest edge at 1024 px. Without sizing
    /// params the docs warn against using baseUrl directly.
    private static func imageUrl(_ base: String) -> URL {
        let sized = base + "=w1024-h1024"
        return URL(string: sized) ?? (URL(string: base) ?? URL(string: "about:blank")!)
    }
}

// MARK: - Errors

enum ImageUploadError: Error, LocalizedError {
    case requiresReauthentication

    var errorDescription: String? {
        switch self {
        case .requiresReauthentication:
            return "Please sign out and sign in again — additional Google Photos access is required."
        }
    }
}

// MARK: - Helpers

private extension GooglePhotosUploader {
    static func errorText(_ data: Data) -> String? {
        let s = String(data: data, encoding: .utf8) ?? ""
        return s.isEmpty ? nil : String(s.prefix(500))
    }
}

// MARK: - Transport

/// Shared HTTP transport for Google Photos uploads.
///
/// Uses a dedicated `.ephemeral` `URLSession` (empty Alt-Svc cache) so
/// uploads negotiate HTTP/2 — sidestepping the CFNetwork HTTP/3
/// response-parsing bug (`NSURLError -1017`) observed on this endpoint.
///
/// A `URLSessionDataDelegate` accumulates the response body per task so we
/// can recover Google's error payload even when the HTTP/2 stream is
/// reset immediately after the response (which URLSession otherwise
/// surfaces as `-1005 "network connection was lost"` with no body).
private final class UploadTransport {
    static let shared = UploadTransport()
    private let session: URLSession
    private let delegate = UploadSessionDelegate()

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 1
        config.waitsForConnectivity = true
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse?) {
        try await delegate.run(task: session.dataTask(with: request))
    }
}

/// Thread-safe per-task body accumulator. Captures the response body even
/// when the HTTP/2 stream is RST after the response headers/body.
private final class UploadSessionDelegate: NSObject, URLSessionDataDelegate {
    private let lock = NSLock()
    private var states: [Int: State] = [:]

    private struct State {
        let continuation: CheckedContinuation<(Data, HTTPURLResponse?), Error>
        var body: Data = Data()
        var response: HTTPURLResponse?
    }

    func run(task: URLSessionDataTask) async throws -> (Data, HTTPURLResponse?) {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            states[task.taskIdentifier] = State(continuation: cont)
            lock.unlock()
            task.resume()
        }
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        if var s = states[dataTask.taskIdentifier], let http = response as? HTTPURLResponse {
            s.response = http
            states[dataTask.taskIdentifier] = s
        }
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        lock.lock()
        if var s = states[dataTask.taskIdentifier] {
            s.body.append(data)
            states[dataTask.taskIdentifier] = s
        }
        lock.unlock()
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        lock.lock()
        let entry = states.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        guard let entry = entry else { return }
        if !entry.body.isEmpty {
            entry.continuation.resume(returning: (entry.body, entry.response))
        } else if let error = error {
            entry.continuation.resume(throwing: error)
        } else {
            entry.continuation.resume(returning: (Data(), entry.response))
        }
    }
}