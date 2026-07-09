import Foundation

public enum PromptSlot: String, CaseIterable, Codable, Equatable, Sendable, Identifiable {
    case `default`
    case customOne
    case customTwo
    case customThree
    case customFour

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .default:
            "D"
        case .customOne:
            "1"
        case .customTwo:
            "2"
        case .customThree:
            "3"
        case .customFour:
            "4"
        }
    }

    public var title: String {
        switch self {
        case .default:
            "Default"
        case .customOne:
            "Custom 1"
        case .customTwo:
            "Custom 2"
        case .customThree:
            "Custom 3"
        case .customFour:
            "Custom 4"
        }
    }
}

public struct PromptTemplateSettings: Codable, Equatable, Sendable {
    public var variantOneSlots: [PromptSlot: String]
    public var variantTwoSlots: [PromptSlot: String]
    public var variantOneSlotNames: [PromptSlot: String]
    public var variantTwoSlotNames: [PromptSlot: String]
    public var activeVariantOneSlot: PromptSlot
    public var activeVariantTwoSlot: PromptSlot
    public var markdownBody: String

    private enum CodingKeys: String, CodingKey {
        case variantOneBody
        case variantTwoBody
        case variantOneSlots
        case variantTwoSlots
        case variantOneSlotNames
        case variantTwoSlotNames
        case activeVariantOneSlot
        case activeVariantTwoSlot
        case markdownBody
    }

    public init(
        variantOneBody: String = PromptTemplate.variantOneDefault.body,
        variantTwoBody: String = PromptTemplate.variantTwoDefault.body,
        markdownBody: String = PromptTemplate.markdownDefault.body
    ) {
        let variantOneSlot = Self.initialActiveSlot(
            body: variantOneBody,
            defaultBody: PromptTemplate.variantOneDefault.body
        )
        let variantTwoSlot = Self.initialActiveSlot(
            body: variantTwoBody,
            defaultBody: PromptTemplate.variantTwoDefault.body
        )
        self.variantOneSlots = Self.initialSlots(
            body: variantOneBody,
            defaultBody: PromptTemplate.variantOneDefault.body,
            activeSlot: variantOneSlot
        )
        self.variantTwoSlots = Self.initialSlots(
            body: variantTwoBody,
            defaultBody: PromptTemplate.variantTwoDefault.body,
            activeSlot: variantTwoSlot
        )
        self.variantOneSlotNames = Self.normalizedSlotNames([:])
        self.variantTwoSlotNames = Self.normalizedSlotNames([:])
        self.activeVariantOneSlot = variantOneSlot
        self.activeVariantTwoSlot = variantTwoSlot
        self.markdownBody = markdownBody
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVariantOneSlots = try container.decodeIfPresent([PromptSlot: String].self, forKey: .variantOneSlots)
        let decodedVariantTwoSlots = try container.decodeIfPresent([PromptSlot: String].self, forKey: .variantTwoSlots)
        let decodedVariantOneSlotNames = try container.decodeIfPresent([PromptSlot: String].self, forKey: .variantOneSlotNames)
        let decodedVariantTwoSlotNames = try container.decodeIfPresent([PromptSlot: String].self, forKey: .variantTwoSlotNames)
        let legacyVariantOneBody = try container.decodeIfPresent(String.self, forKey: .variantOneBody)
        let legacyVariantTwoBody = try container.decodeIfPresent(String.self, forKey: .variantTwoBody)

        if let decodedVariantOneSlots {
            variantOneSlots = Self.normalizedSlots(
                decodedVariantOneSlots,
                defaultBody: PromptTemplate.variantOneDefault.body
            )
        } else {
            let body = legacyVariantOneBody ?? PromptTemplate.variantOneDefault.body
            let activeSlot = Self.initialActiveSlot(
                body: body,
                defaultBody: PromptTemplate.variantOneDefault.body
            )
            variantOneSlots = Self.initialSlots(
                body: body,
                defaultBody: PromptTemplate.variantOneDefault.body,
                activeSlot: activeSlot
            )
        }

        if let decodedVariantTwoSlots {
            variantTwoSlots = Self.normalizedSlots(
                decodedVariantTwoSlots,
                defaultBody: PromptTemplate.variantTwoDefault.body
            )
        } else {
            let body = legacyVariantTwoBody ?? PromptTemplate.variantTwoDefault.body
            let activeSlot = Self.initialActiveSlot(
                body: body,
                defaultBody: PromptTemplate.variantTwoDefault.body
            )
            variantTwoSlots = Self.initialSlots(
                body: body,
                defaultBody: PromptTemplate.variantTwoDefault.body,
                activeSlot: activeSlot
            )
        }

        variantOneSlotNames = Self.normalizedSlotNames(decodedVariantOneSlotNames ?? [:])
        variantTwoSlotNames = Self.normalizedSlotNames(decodedVariantTwoSlotNames ?? [:])

        activeVariantOneSlot = try container.decodeIfPresent(PromptSlot.self, forKey: .activeVariantOneSlot)
            ?? Self.initialActiveSlot(
                body: legacyVariantOneBody ?? PromptTemplate.variantOneDefault.body,
                defaultBody: PromptTemplate.variantOneDefault.body
            )
        activeVariantTwoSlot = try container.decodeIfPresent(PromptSlot.self, forKey: .activeVariantTwoSlot)
            ?? Self.initialActiveSlot(
                body: legacyVariantTwoBody ?? PromptTemplate.variantTwoDefault.body,
                defaultBody: PromptTemplate.variantTwoDefault.body
            )
        markdownBody = try container.decodeIfPresent(String.self, forKey: .markdownBody)
            ?? PromptTemplate.markdownDefault.body
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(variantOneSlots, forKey: .variantOneSlots)
        try container.encode(variantTwoSlots, forKey: .variantTwoSlots)
        try container.encode(variantOneSlotNames, forKey: .variantOneSlotNames)
        try container.encode(variantTwoSlotNames, forKey: .variantTwoSlotNames)
        try container.encode(activeVariantOneSlot, forKey: .activeVariantOneSlot)
        try container.encode(activeVariantTwoSlot, forKey: .activeVariantTwoSlot)
        try container.encode(markdownBody, forKey: .markdownBody)
    }

    public var variantOneBody: String {
        get { body(for: .variantOne) }
        set { setBody(newValue, for: .variantOne) }
    }

    public var variantTwoBody: String {
        get { body(for: .variantTwo) }
        set { setBody(newValue, for: .variantTwo) }
    }

    public func body(for variant: ProcessingVariant) -> String {
        switch variant {
        case .raw, .variantOne:
            resolvedBody(
                in: activeVariantOneSlot,
                slots: variantOneSlots,
                defaultBody: PromptTemplate.variantOneDefault.body
            )
        case .variantTwo:
            resolvedBody(
                in: activeVariantTwoSlot,
                slots: variantTwoSlots,
                defaultBody: PromptTemplate.variantTwoDefault.body
            )
        }
    }

    public func body(in slot: PromptSlot, for variant: ProcessingVariant) -> String {
        switch variant {
        case .raw, .variantOne:
            variantOneSlots[slot] ?? ""
        case .variantTwo:
            variantTwoSlots[slot] ?? ""
        }
    }

    public func activeSlot(for variant: ProcessingVariant) -> PromptSlot {
        switch variant {
        case .raw, .variantOne:
            activeVariantOneSlot
        case .variantTwo:
            activeVariantTwoSlot
        }
    }

    public func slotName(in slot: PromptSlot, for variant: ProcessingVariant) -> String {
        let names: [PromptSlot: String]
        switch variant {
        case .raw, .variantOne:
            names = variantOneSlotNames
        case .variantTwo:
            names = variantTwoSlotNames
        }

        return Self.normalizedSlotName(names[slot], fallback: slot.title)
    }

    public func template(for variant: ProcessingVariant) -> PromptTemplate {
        switch variant {
        case .raw, .variantOne:
            PromptTemplate(
                id: "variant-one-custom",
                title: ProcessingVariant.variantOne.title,
                body: variantOneBody
            )
        case .variantTwo:
            PromptTemplate(
                id: "variant-two-custom",
                title: ProcessingVariant.variantTwo.title,
                body: variantTwoBody
            )
        }
    }

    public mutating func setBody(_ body: String, for variant: ProcessingVariant) {
        switch variant {
        case .raw, .variantOne:
            variantOneSlots[activeVariantOneSlot] = body
        case .variantTwo:
            variantTwoSlots[activeVariantTwoSlot] = body
        }
    }

    public mutating func reset(_ variant: ProcessingVariant) {
        switch variant {
        case .raw, .variantOne:
            variantOneSlots[activeVariantOneSlot] = activeVariantOneSlot == .default
                ? PromptTemplate.variantOneDefault.body
                : ""
        case .variantTwo:
            variantTwoSlots[activeVariantTwoSlot] = activeVariantTwoSlot == .default
                ? PromptTemplate.variantTwoDefault.body
                : ""
        }
    }

    public mutating func setActiveSlot(_ slot: PromptSlot, for variant: ProcessingVariant) {
        switch variant {
        case .raw, .variantOne:
            activeVariantOneSlot = slot
            variantOneSlots = Self.normalizedSlots(
                variantOneSlots,
                defaultBody: PromptTemplate.variantOneDefault.body
            )
        case .variantTwo:
            activeVariantTwoSlot = slot
            variantTwoSlots = Self.normalizedSlots(
                variantTwoSlots,
                defaultBody: PromptTemplate.variantTwoDefault.body
            )
        }
    }

    public mutating func setBody(_ body: String, in slot: PromptSlot, for variant: ProcessingVariant) {
        switch variant {
        case .raw, .variantOne:
            variantOneSlots[slot] = body
        case .variantTwo:
            variantTwoSlots[slot] = body
        }
    }

    public mutating func setSlotName(_ name: String, in slot: PromptSlot, for variant: ProcessingVariant) {
        guard slot != .default else { return }

        switch variant {
        case .raw, .variantOne:
            variantOneSlotNames[slot] = name
        case .variantTwo:
            variantTwoSlotNames[slot] = name
        }
    }

    public mutating func setMarkdownBody(_ body: String) {
        markdownBody = body
    }

    public mutating func resetMarkdown() {
        markdownBody = PromptTemplate.markdownDefault.body
    }

    public func markdownTemplate() -> PromptTemplate {
        PromptTemplate(
            id: "markdown-custom",
            title: "Markdown",
            body: markdownBody
        )
    }

    public func migratedToLatestDefaults() -> PromptTemplateSettings {
        var migrated = self

        let activeVariantOneBody = migrated.body(for: .variantOne)
        if activeVariantOneBody == PromptTemplate.variantOneLegacyDefault.body {
            migrated.variantOneSlots[migrated.activeVariantOneSlot] = migrated.activeVariantOneSlot == .default
                ? PromptTemplate.variantOneDefault.body
                : ""
            migrated.variantOneSlots[.default] = PromptTemplate.variantOneDefault.body
            migrated.activeVariantOneSlot = .default
        }

        let activeVariantTwoBody = migrated.body(for: .variantTwo)
        if activeVariantTwoBody == PromptTemplate.variantTwoLegacyDefault.body
            || activeVariantTwoBody == PromptTemplate.variantTwoClarityDefault.body
            || activeVariantTwoBody == PromptTemplate.variantTwoAggressiveDefault.body
            || Self.isPromptImprovementTemplate(activeVariantTwoBody) {
            migrated.variantTwoSlots[migrated.activeVariantTwoSlot] = migrated.activeVariantTwoSlot == .default
                ? PromptTemplate.variantTwoDefault.body
                : ""
            migrated.variantTwoSlots[.default] = PromptTemplate.variantTwoDefault.body
            migrated.activeVariantTwoSlot = .default
        }

        if migrated.markdownBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || Self.normalizedPromptBody(migrated.markdownBody) == Self.normalizedPromptBody(PromptTemplate.markdownLegacyDefault.body) {
            migrated.markdownBody = PromptTemplate.markdownDefault.body
        }

        migrated.variantOneSlots = Self.normalizedSlots(
            migrated.variantOneSlots,
            defaultBody: PromptTemplate.variantOneDefault.body
        )
        migrated.variantTwoSlots = Self.normalizedSlots(
            migrated.variantTwoSlots,
            defaultBody: PromptTemplate.variantTwoDefault.body
        )
        migrated.variantOneSlotNames = Self.normalizedSlotNames(migrated.variantOneSlotNames)
        migrated.variantTwoSlotNames = Self.normalizedSlotNames(migrated.variantTwoSlotNames)

        return migrated
    }

    private static func isPromptImprovementTemplate(_ body: String) -> Bool {
        let normalized = body
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")

        let markers = [
            "возьми этот промпт",
            "радикально улучши",
            "в 4 раза по ясности",
            "силу воздействия",
            "продвинутой языковой модели",
            "prompt engineering"
        ]

        return markers.contains { normalized.contains($0) }
    }

    private static func normalizedPromptBody(_ body: String) -> String {
        body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolvedBody(
        in slot: PromptSlot,
        slots: [PromptSlot: String],
        defaultBody: String
    ) -> String {
        let body = slots[slot] ?? ""
        if slot != .default && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return defaultBody
        }
        return body
    }

    private static func initialActiveSlot(body: String, defaultBody: String) -> PromptSlot {
        body == defaultBody ? .default : .customOne
    }

    private static func initialSlots(
        body: String,
        defaultBody: String,
        activeSlot: PromptSlot
    ) -> [PromptSlot: String] {
        var slots = normalizedSlots([:], defaultBody: defaultBody)
        slots[activeSlot] = body
        return slots
    }

    private static func normalizedSlots(
        _ slots: [PromptSlot: String],
        defaultBody: String
    ) -> [PromptSlot: String] {
        var normalized = slots
        for slot in PromptSlot.allCases where normalized[slot] == nil {
            normalized[slot] = slot == .default ? defaultBody : ""
        }
        if (normalized[.default] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized[.default] = defaultBody
        }
        return normalized
    }

    private static func normalizedSlotNames(_ names: [PromptSlot: String]) -> [PromptSlot: String] {
        var normalized = names
        for slot in PromptSlot.allCases {
            normalized[slot] = normalizedSlotName(normalized[slot], fallback: slot.title)
        }
        normalized[.default] = PromptSlot.default.title
        return normalized
    }

    private static func normalizedSlotName(_ name: String?, fallback: String) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
