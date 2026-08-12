import Foundation

// Pure Core ranking for onboarding local ASR models. UI language and
// installation state stay outside this function; the selected speech pair and
// each model's capability contract determine eligibility and ordering.
public enum OnboardingModelRecommendation {
    public enum Role: String, Sendable {
        case gigaAMRussian
        case canaryFlash180M
        case canary1B
        case whisperLargeV3
        case whisperLargeV3Turbo
        case whisperMediumMultilingual
        case whisperSmallMultilingual
        case whisperMediumEnglish
        case whisperSmallEnglish
        case parakeet
    }

    /// Returns up to three available models that can transcribe the selected
    /// primary language. Models supporting both primary and additional speech
    /// languages rank ahead of primary-only models, while Russian keeps its
    /// dedicated GigaAM recommendation first when Russian is primary.
    public static func topThree(
        primary: String,
        additional: String,
        available: [TranscriptionModelDescriptor]
    ) -> [TranscriptionModelDescriptor] {
        let primaryCode = normalizeLanguageCode(primary)
        let additionalCode = normalizeLanguageCode(additional)
        let preferredRoles = preferredRoles(primary: primaryCode, additional: additionalCode)
        let roleRanks = Dictionary(
            uniqueKeysWithValues: preferredRoles.enumerated().map { index, role in
                (role, index)
            }
        )

        var seenIDs = Set<String>()
        let candidates = available.enumerated().compactMap { index, model -> Candidate? in
            guard seenIDs.insert(model.id).inserted else { return nil }

            // A model that cannot transcribe the main dictation language is
            // never a useful onboarding recommendation. An empty primary is
            // retained as a defensive fallback for legacy settings snapshots.
            let supportsPrimary = primaryCode.isEmpty
                || model.capabilities.supportsInputLanguage(primaryCode)
            guard supportsPrimary else { return nil }

            let coverage = languageCoverage(
                model: model,
                primary: primaryCode,
                additional: additionalCode
            )
            let role = role(for: model.id)
            let roleRank = role.flatMap { roleRanks[$0] } ?? preferredRoles.count
            let russianSpecialty = primaryCode == "ru" && role == .gigaAMRussian

            return Candidate(
                model: model,
                originalIndex: index,
                coverage: coverage,
                roleRank: roleRank,
                russianSpecialty: russianSpecialty
            )
        }

        return candidates
            .sorted { lhs, rhs in
                if lhs.russianSpecialty != rhs.russianSpecialty {
                    return lhs.russianSpecialty
                }
                if lhs.coverage != rhs.coverage {
                    return lhs.coverage > rhs.coverage
                }
                if lhs.roleRank != rhs.roleRank {
                    return lhs.roleRank < rhs.roleRank
                }
                if lhs.model.accuracy != rhs.model.accuracy {
                    return lhs.model.accuracy > rhs.model.accuracy
                }
                if lhs.model.speed != rhs.model.speed {
                    return lhs.model.speed > rhs.model.speed
                }
                return lhs.originalIndex < rhs.originalIndex
            }
            .prefix(3)
            .map(\.model)
    }

    private struct Candidate {
        let model: TranscriptionModelDescriptor
        let originalIndex: Int
        let coverage: Int
        let roleRank: Int
        let russianSpecialty: Bool
    }

    private static let canaryFlashLanguages: Set<String> = ["en", "de", "fr", "es"]

    private static func preferredRoles(primary: String, additional: String) -> [Role] {
        if primary == "ru" {
            // RU-first ordering is intentional: GigaAM is the specialized
            // Russian option, followed by the fast multilingual candidates,
            // then Whisper quality tiers.
            return [
                .gigaAMRussian,
                .parakeet,
                .canary1B,
                .whisperLargeV3,
                .whisperLargeV3Turbo,
                .whisperMediumMultilingual,
                .whisperSmallMultilingual,
                .canaryFlash180M,
                .whisperMediumEnglish,
                .whisperSmallEnglish
            ]
        }

        if canaryFlashLanguages.contains(primary),
           canaryFlashLanguages.contains(additional),
           !additional.isEmpty {
            return [
                .canaryFlash180M,
                .parakeet,
                .canary1B,
                .whisperLargeV3,
                .whisperLargeV3Turbo,
                .whisperMediumMultilingual,
                .whisperSmallMultilingual,
                .whisperSmallEnglish,
                .whisperMediumEnglish
            ]
        }

        if canaryFlashLanguages.contains(primary) {
            // Keep English/German/French/Spanish fast candidates near the top
            // when the second selected language is outside Flash's four-
            // language contract. Coverage still wins below, so a multilingual
            // Whisper model moves ahead when it is the only model supporting
            // both selected languages.
            return [
                .parakeet,
                .canary1B,
                .canaryFlash180M,
                .whisperLargeV3,
                .whisperLargeV3Turbo,
                .whisperMediumMultilingual,
                .whisperSmallMultilingual,
                .whisperSmallEnglish,
                .whisperMediumEnglish
            ]
        }

        // For languages outside the compact Canary Flash set, prefer the
        // broad Whisper tiers. The capability filter below keeps this list
        // honest for languages such as Korean, Hindi, Arabic, and Chinese.
        return [
            .whisperLargeV3,
            .whisperLargeV3Turbo,
            .whisperMediumMultilingual,
            .parakeet,
            .canary1B,
            .whisperSmallMultilingual,
            .canaryFlash180M,
            .whisperMediumEnglish,
            .whisperSmallEnglish
        ]
    }

    private static func languageCoverage(
        model: TranscriptionModelDescriptor,
        primary: String,
        additional: String
    ) -> Int {
        var coverage = 0
        if !primary.isEmpty && model.capabilities.supportsInputLanguage(primary) {
            coverage += 1
        }
        if !additional.isEmpty,
           additional != primary,
           model.capabilities.supportsInputLanguage(additional) {
            coverage += 1
        }
        return coverage
    }

    private static func normalizeLanguageCode(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")

        guard !normalized.isEmpty else { return "" }
        if let canonical = LanguagePickerOrder.speechCode(forNameOrCode: normalized) {
            return canonical
        }
        return normalized.split(separator: "-").first.map(String.init) ?? normalized
    }

    private static func role(for modelID: String) -> Role? {
        switch modelID {
        case "gigaam-v3-rnnt-coreml":
            .gigaAMRussian
        case "canary-180m-flash-coreml":
            .canaryFlash180M
        case "canary-1b-v2-coreml":
            .canary1B
        case "whisperkit-large-v3-full":
            .whisperLargeV3
        case "whisperkit-large-v3-turbo":
            .whisperLargeV3Turbo
        case "whisperkit-medium-multilingual":
            .whisperMediumMultilingual
        case "whisperkit-small-multilingual":
            .whisperSmallMultilingual
        case "whisperkit-medium-en":
            .whisperMediumEnglish
        case "whisperkit-small-en":
            .whisperSmallEnglish
        case "parakeet-tdt-06b-v3":
            .parakeet
        default:
            nil
        }
    }
}
