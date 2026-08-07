import Foundation

/// Errors thrown by the Blogger API client.
enum BloggerError: Error, LocalizedError {
    case noAccessToken
    case http(statusCode: Int, message: String?)
    case decoding(Error)
    case invalidURL
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .noAccessToken:
            return "You are not signed in. Please sign in to continue."
        case .http(let code, let message):
            let detail = message.flatMap { ": \($0)" } ?? ""
            return "Request failed (\(code))\(detail)"
        case .decoding(let err):
            return "Failed to read the server response: \(err.localizedDescription)"
        case .invalidURL:
            return "Invalid URL."
        case .emptyResponse:
            return "The server returned no data."
        }
    }
}
