import Foundation

public struct HuggingFaceModelManifest: Decodable, Equatable, Sendable {
    public let files: [String]

    private enum CodingKeys: String, CodingKey {
        case siblings
    }

    private struct Sibling: Decodable {
        let fileName: String?

        private enum CodingKeys: String, CodingKey {
            case rfilename
            case rpath
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            fileName = try container.decodeIfPresent(String.self, forKey: .rfilename)
                ?? container.decodeIfPresent(String.self, forKey: .rpath)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let siblings = try container.decodeIfPresent([Sibling].self, forKey: .siblings) ?? []
        files = siblings.compactMap(\.fileName)
    }
}
