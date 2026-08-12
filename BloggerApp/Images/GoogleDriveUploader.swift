import Foundation
import GoogleSignIn

/// Uploads images to the user's Google Drive and returns a permanent,
/// publicly-embeddable URL for use in blog post HTML.
///
/// Why Drive instead of Photos: the Photos Library API returns `baseUrl`s
/// that expire after 60 minutes, breaking embedded images in published posts.
/// Drive files keep a stable URL as long as the file exists.
///
/// Flow:
///   1. Upload the image bytes with `uploadType=multipart` (metadata + bytes)
///      → returns the new file's `id`. Requires `drive.file` scope, which only
///      grants access to files created by this app.
///   2. Set the file's sharing permission to "anyone with link" (reader) so
///      the URL works in a public blog post without authentication.
///   3. Return the file's Googleusercontent CDN URL
///      (`https://lh3.googleusercontent.com/d/<id>=w1024-h1024`) — permanent
///      and served directly as image bytes. (The `uc?export=view` URL
///      redirects to a download endpoint that browsers reject in `<img>`.)
struct GoogleDriveUploader: ImageUploading {
    private static let baseURL = URL(string: "https://www.googleapis.com")!
    private static var transport: UploadTransport { .shared }

    func upload(imageData: Data, contentType: String) async throws -> URL {
        let token = try await AuthManager.shared.currentAccessToken()
        let fileID = try await uploadFile(data: imageData, contentType: contentType, token: token)
        try await makePublic(fileID: fileID, token: token)
        return URL(string: "https://lh3.googleusercontent.com/d/\(fileID)=w1024-h1024")!
    }
}

// MARK: - Step 1: upload bytes (multipart)

private extension GoogleDriveUploader {
    /// POSTs a multipart body (JSON metadata part + binary part) to
    /// `/upload/drive/v3/files?uploadType=multipart` and returns the file id.
    func uploadFile(data: Data, contentType: String, token: String) async throws -> String {
        let boundary = "BloggerApp-\(UUID().uuidString)"

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        let metadata = #"{"name":"image.jpg","mimeType":"\#(contentType)"}"#
        body.append(metadata.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: Self.baseURL
            .appendingPathComponent("upload/drive/v3/files")
            .appending(queryItems: [URLQueryItem(name: "uploadType", value: "multipart")]))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        struct Response: Decodable {
            let id: String
        }

        let (responseBody, response) = try await Self.transport.send(request)
        guard let http = response, (200..<300).contains(http.statusCode) else {
            throw BloggerError.http(statusCode: response?.statusCode ?? -1,
                                    message: Self.errorText(responseBody))
        }
        do {
            let decoded = try JSONDecoder().decode(Response.self, from: responseBody)
            return decoded.id
        } catch {
            let raw = String(data: responseBody, encoding: .utf8) ?? "<binary>"
            NSLog("[DriveUpload] decode failed: \(raw.prefix(500))")
            throw BloggerError.http(statusCode: http.statusCode,
                                    message: "Bad response: \(raw.prefix(500))")
        }
    }
}

// MARK: - Step 2: make public

private extension GoogleDriveUploader {
    /// Shares the file as "anyone with the link" (reader) so the image URL
    /// renders in public posts. Uses a JSON body per the Drive API docs.
    func makePublic(fileID: String, token: String) async throws {
        var request = URLRequest(url: Self.baseURL
            .appendingPathComponent("drive/v3/files/\(fileID)/permissions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = #"{"role":"reader","type":"anyone"}"#.data(using: .utf8)!

        let (responseBody, response) = try await Self.transport.send(request)
        guard let http = response, (200..<300).contains(http.statusCode) else {
            throw BloggerError.http(statusCode: response?.statusCode ?? -1,
                                    message: Self.errorText(responseBody))
        }
    }
}

// MARK: - Helpers

private extension GoogleDriveUploader {
    static func errorText(_ data: Data) -> String? {
        let s = String(data: data, encoding: .utf8) ?? ""
        return s.isEmpty ? nil : String(s.prefix(500))
    }
}

// MARK: - Transport

/// Shared HTTP transport for Google API calls.
///
/// Uses a dedicated `.ephemeral` `URLSession` (empty Alt-Svc cache) so
/// requests negotiate HTTP/2 — sidestepping the CFNetwork HTTP/3
/// response-parsing bug (`NSURLError -1017`) observed on Google endpoints.
///
/// A `URLSessionDataDelegate` accumulates the response body per task so we
/// can recover Google's error payload even when the HTTP/2 stream is reset
/// immediately after the response (which URLSession otherwise surfaces as
/// `-1005 "network connection was lost"` with no body).
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
