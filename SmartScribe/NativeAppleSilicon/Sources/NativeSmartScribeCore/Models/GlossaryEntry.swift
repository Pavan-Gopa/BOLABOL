import Foundation

public struct GlossaryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var variants: [String]
    public var source: String
    public var translation: String
    public var category: String?
    public var translations: [String: String]
    public var remember: Bool
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String,
        variants: [String],
        source: String,
        translation: String,
        category: String?,
        translations: [String: String],
        remember: Bool,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.variants = variants
        self.source = source
        self.translation = translation
        self.category = category
        self.translations = translations
        self.remember = remember
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
