import Foundation

/// Frozen per-session target-language snapshot (ADR-029).
///
/// Captured once when hotkey recording starts. Only an explicit HUD action
/// during that recording (language tap, target tap, picker selection)
/// replaces it. Stop hands it unchanged into the processing pipeline;
/// later toggles affect the next session only.
public enum HotkeyTranslationMechanism: String, Codable, Equatable, Sendable {
    case none
    case nativeASR
    case polishing
}

public struct HotkeyLanguageSnapshot: Equatable, Sendable {
    public var wantsTarget: Bool
    public var targetCode: String?
    public var mechanism: HotkeyTranslationMechanism
    public var hudLetter: String
    public var letterEnabled: Bool
    public var hotkeyTarget: HotkeyTarget

    public init(
        wantsTarget: Bool,
        targetCode: String?,
        mechanism: HotkeyTranslationMechanism,
        hudLetter: String,
        letterEnabled: Bool,
        hotkeyTarget: HotkeyTarget
    ) {
        self.wantsTarget = wantsTarget
        self.targetCode = targetCode
        self.mechanism = mechanism
        self.hudLetter = hudLetter
        self.letterEnabled = letterEnabled
        self.hotkeyTarget = hotkeyTarget
    }

    public static func inactive(for target: HotkeyTarget) -> HotkeyLanguageSnapshot {
        HotkeyLanguageSnapshot(
            wantsTarget: false,
            targetCode: nil,
            mechanism: .none,
            hudLetter: "A",
            letterEnabled: false,
            hotkeyTarget: target
        )
    }
}
extension HotkeyLanguageSnapshot {
    /// ADR-029 (J1): explicit HUD language/target action during recording.
    ///
    /// The refreshed snapshot always replaces the frozen one — even when no
    /// local session can be built (Gemini cloud dictation has no local
    /// session, so session resolution returns `.unavailable`). Only the
    /// `pendingHotkeySession` replacement is gated on availability.
    public static func snapshotAfterExplicitHUDAction(
        current: HotkeyLanguageSnapshot?,
        refreshed: HotkeyLanguageSnapshot,
        localSessionAvailable: Bool
    ) -> HotkeyLanguageSnapshot {
        // Unconditional by design: availability gates only the local session.
        refreshed
    }
}

/// Pure capability-truthful resolver shared by idle HUD and session freeze.
public enum HotkeyLanguageSnapshotResolver {
    /// ADR-029 (J1): the one call-site formula for `wantsTargetOutput`.
    ///
    /// The user's E/target choice, independent of processing target. Raw
    /// exclusion must never live here: `resolve` already decides capability
    /// (Raw → nativeASR only for Gemini or native-translation Whisper,
    /// otherwise inactive). Every freeze/refresh passes this through.
    public static func userWantsTargetOutput(
        for target: HotkeyTarget,
        forceTargetLanguage: Bool
    ) -> Bool {
        _ = target
        return forceTargetLanguage
    }

    /// - Parameters:
    ///   - hotkeyTarget: R / 1 / 2 processing target.
    ///   - wantsTargetOutput: persisted HUD force-target flag (E on).
    ///   - requestedTargetCode: concrete HUD target code (e.g. "en").
    ///   - backend: active transcription backend, or nil when unknown.
    ///   - modelSupportsNativeTranslation: true only for natively translating
    ///     ASR models (Whisper large-v3 full/medium/small multilingual → en).
    ///   - isGeminiCloud: Gemini dictation backend (natively translates to any).
    ///   - polishingCanTranslate: cloud provider with keys or downloaded MLX.
    public static func resolve(
        hotkeyTarget: HotkeyTarget,
        wantsTargetOutput: Bool,
        requestedTargetCode: String?,
        backend: TranscriptionModelDescriptor.Backend?,
        modelSupportsNativeTranslation: Bool,
        isGeminiCloud: Bool,
        polishingCanTranslate: Bool
    ) -> HotkeyLanguageSnapshot {
        guard wantsTargetOutput,
              let rawCode = requestedTargetCode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawCode.isEmpty,
              rawCode.lowercased() != "auto"
        else {
            return .inactive(for: hotkeyTarget)
        }
        let code = rawCode.lowercased()

        switch hotkeyTarget {
        case .raw:
            if isGeminiCloud {
                return HotkeyLanguageSnapshot(
                    wantsTarget: true,
                    targetCode: code,
                    mechanism: .nativeASR,
                    hudLetter: TranscriptionLanguageOption.hudLabel(for: code),
                    letterEnabled: true,
                    hotkeyTarget: hotkeyTarget
                )
            }
            // Native ASR translation is English-only (Whisper translate task).
            guard code == "en", modelSupportsNativeTranslation else {
                return .inactive(for: hotkeyTarget)
            }
            _ = backend
            return HotkeyLanguageSnapshot(
                wantsTarget: true,
                targetCode: code,
                mechanism: .nativeASR,
                hudLetter: TranscriptionLanguageOption.hudLabel(for: code),
                letterEnabled: true,
                hotkeyTarget: hotkeyTarget
            )
        case .note, .x2:
            guard polishingCanTranslate else {
                return .inactive(for: hotkeyTarget)
            }
            return HotkeyLanguageSnapshot(
                wantsTarget: true,
                targetCode: code,
                mechanism: .polishing,
                hudLetter: TranscriptionLanguageOption.hudLabel(for: code),
                letterEnabled: true,
                hotkeyTarget: hotkeyTarget
            )
        }
    }
}
