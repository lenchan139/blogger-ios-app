import Foundation
import UIKit

/// Abstraction over image hosting so the post editor can embed images
/// regardless of the provider. The Blogger API has no upload endpoint, so
/// images are hosted elsewhere (e.g. Google Photos) and referenced by URL.
protocol ImageUploading {
    /// Uploads image data and returns the absolute URL to embed in post HTML.
    func upload(imageData: Data, contentType: String) async throws -> URL
}
