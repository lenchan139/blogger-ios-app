import Foundation

/// Decodes an integer that Blogger may return as either a JSON number or a
/// quoted string (e.g. `"totalItems": 494` vs `"totalItems": "0"`).
struct FlexibleInt: Codable, Equatable {
    let value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let string = try? container.decode(String.self) {
            value = Int(string) ?? 0
        } else {
            value = 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
