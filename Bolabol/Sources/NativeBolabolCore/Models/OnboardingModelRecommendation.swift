import Foundation

// Pure Core ranking for onboarding local ASR models. UI language and installation
// state stay outside this function; only the primary/additional speech pair matters.
public enum OnboardingModelRecommendation {
    public enum Role: String, Sendable {
        case gigaAMRussian
        case canaryFlash180M
        case canary1B
        case whisperLargeV3
        case whisperLargeV3Turbo
        case parakeet
    }

    /// Returns up to three available models in the plan's R1/R2/R3 order.
    public static func topThree(
        primary: String,
        additional: String,
        available: [TranscriptionModelDescriptor]
    ) -> [TranscriptionModelDescriptor] {
        let normalizedPrimary = normalizeLanguageCode(primary)
        let normalizedAdditional = normalizeLanguageCode(additional)
        let roles: [Role]

        if normalizedPrimary == "ru" || normalizedAdditional == "ru" {
            if canaryFlashLanguages.contains(normalizedAdditional) {
                roles = [.gigaAMRussian, .canaryFlash180M, .whisperLargeV3]
            } else {
                roles = [.gigaAMRussian, .whisperLargeV3, .whisperLargeV3Turbo]
            }
        } else if canaryFlashLanguages.contains(normalizedPrimary),
                  canaryFlashLanguages.contains(normalizedAdditional) {
            roles = [.canaryFlash180M, .whisperLargeV3, .whisperLargeV3Turbo]
        } else {
            roles = [
                .whisperLargeV3,
                .whisperLargeV3Turbo,
                .canary1B,
                .parakeet,
                .canaryFlash180M
            ]
        }

        var selectedIDs = Set<String>()
        var result: [TranscriptionModelDescriptor] = []

        for role in roles {
            let modelID = modelID(for: role)
            guard let model = available.first(where: { $0.id == modelID }),
                  selectedIDs.insert(model.id).inserted else {
                continue
            }

            result.append(model)
            if result.count == 3 {
                break
            }
        }

        return result
    }

    private static let canaryFlashLanguages: Set<String> = ["en", "de", "fr", "es"]

    private static func normalizeLanguageCode(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func modelID(for role: Role) -> String {
        switch role {
        case .gigaAMRussian:
            "gigaam-v3-rnnt-coreml"
        case .canaryFlash180M:
            "canary-180m-flash-coreml"
        case .canary1B:
            "canary-1b-v2-coreml"
        case .whisperLargeV3:
            "whisperkit-large-v3-full"
        case .whisperLargeV3Turbo:
            "whisperkit-large-v3-turbo"
        case .parakeet:
            "parakeet-tdt-06b-v3"
        }
    }
}
