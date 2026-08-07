import Foundation

public struct TranscriptionLanguageRoute: Equatable, Sendable {
    public var forcedLanguageCode: String?
    public var translateToEnglish: Bool
    public var postASRTextTranslationTargetLanguageCode: String?

    public init(
        forcedLanguageCode: String?,
        translateToEnglish: Bool,
        postASRTextTranslationTargetLanguageCode: String?
    ) {
        self.forcedLanguageCode = forcedLanguageCode
        self.translateToEnglish = translateToEnglish
        self.postASRTextTranslationTargetLanguageCode = postASRTextTranslationTargetLanguageCode
    }
}

/// The operation requested when a local transcription session is created.
///
/// `.asr` is the only speech operation accepted by non-Whisper backends.
/// Target-output intent is typed as Whisper-only and never carries a generic
/// speech target into a transcription request.
public enum TranscriptionSessionOperation: Equatable, Sendable {
    case asr
    case whisperTargetTranslation(languageCode: String)
}

/// Availability facts captured together with the model snapshot. These are
/// inputs to the pure resolver, not persisted installation state.
public struct TranscriptionSessionAvailability: Equatable, Sendable {
    public let currentOSVersion: ASRModelCapabilities.OSVersion
    public let hasCompleteModel: Bool

    public init(
        currentOSVersion: ASRModelCapabilities.OSVersion,
        hasCompleteModel: Bool
    ) {
        self.currentOSVersion = currentOSVersion
        self.hasCompleteModel = hasCompleteModel
    }
}

/// A non-persisted notice for a Canary session that had to use a supported
/// additional language because the configured primary language is unsupported.
public struct TranscriptionSessionLanguageWarning: Equatable, Sendable {
    public let primaryLanguageCode: String
    public let effectiveSourceLanguageCode: String

    public init(
        primaryLanguageCode: String,
        effectiveSourceLanguageCode: String
    ) {
        self.primaryLanguageCode = primaryLanguageCode
        self.effectiveSourceLanguageCode = effectiveSourceLanguageCode
    }
}

/// Frozen inputs used to build one session plan. A caller supplies the active
/// complete descriptor and presence facts from the same moment; the resolver
/// does not inspect mutable stores and never writes user settings.
public struct TranscriptionSessionSnapshot: Equatable, Sendable {
    public let activeModel: TranscriptionModelDescriptor?
    public let modelFolderURL: URL?
    public let engineIdentity: String?
    public let capabilities: ASRModelCapabilities?
    public let availability: TranscriptionSessionAvailability
    public let primaryLanguageCode: String?
    public let additionalLanguageCode: String?
    public let operation: TranscriptionSessionOperation
    public let legacyLanguageCode: String?
    /// Ephemeral source selection for explicit-source backends. This is never
    /// persisted and is intentionally separate from the legacy Whisper field.
    public let sourceLanguageOverride: String?

    public init(
        activeModel: TranscriptionModelDescriptor?,
        modelFolderURL: URL? = nil,
        engineIdentity: String? = nil,
        capabilities: ASRModelCapabilities? = nil,
        availability: TranscriptionSessionAvailability,
        primaryLanguageCode: String?,
        additionalLanguageCode: String?,
        operation: TranscriptionSessionOperation,
        legacyLanguageCode: String? = nil,
        sourceLanguageOverride: String? = nil
    ) {
        self.activeModel = activeModel
        self.modelFolderURL = modelFolderURL
        self.engineIdentity = engineIdentity
        self.capabilities = capabilities
        self.availability = availability
        self.primaryLanguageCode = primaryLanguageCode
        self.additionalLanguageCode = additionalLanguageCode
        self.operation = operation
        self.legacyLanguageCode = legacyLanguageCode
        self.sourceLanguageOverride = sourceLanguageOverride
    }
}

/// A typed reason why a session cannot be created. Each case is terminal for
/// the current request: callers must not invoke an engine or silently choose a
/// different model, source language, or backend.
public enum TranscriptionSessionUnavailableReason: Error, Equatable, Sendable {
    case noActiveModel
    case incompleteModel(modelID: String)
    case unsupportedOS(
        modelID: String,
        required: ASRModelCapabilities.OSVersion,
        current: ASRModelCapabilities.OSVersion
    )
    case invalidCapabilities(modelID: String)
    case noSupportedSource(modelID: String, supportedCodes: [String])
    case unsupportedSourceLanguage(
        modelID: String,
        requestedCode: String,
        supportedCodes: [String]
    )
    case englishSourceRequired(modelID: String)
    case translationUnsupported(modelID: String)
    case unsupportedOperation(modelID: String)
    case engineIdentityMismatch(modelID: String)

    public var modelID: String? {
        switch self {
        case .noActiveModel:
            nil
        case .incompleteModel(let modelID),
             .invalidCapabilities(let modelID),
             .unsupportedSourceLanguage(let modelID, _, _),
             .englishSourceRequired(let modelID),
             .translationUnsupported(let modelID),
             .unsupportedOperation(let modelID),
             .engineIdentityMismatch(let modelID):
            modelID
        case .unsupportedOS(let modelID, _, _),
             .noSupportedSource(let modelID, _):
            modelID
        }
    }

    public var errorDescription: String? {
        switch self {
        case .noActiveModel:
            "No active transcription model is available."
        case .incompleteModel(let modelID):
            "The local model \(modelID) is incomplete."
        case .unsupportedOS(let modelID, let required, let current):
            "The local model \(modelID) requires macOS \(required.majorVersion).\(required.minorVersion); current macOS is \(current.majorVersion).\(current.minorVersion)."
        case .invalidCapabilities(let modelID):
            "The local model \(modelID) has no verified explicit ASR source."
        case .noSupportedSource(let modelID, let supportedCodes):
            "The local model \(modelID) needs one of: \(supportedCodes.joined(separator: ", "))."
        case .unsupportedSourceLanguage(let modelID, let requestedCode, let supportedCodes):
            "The local model \(modelID) does not support \(requestedCode) as an input language. Supported inputs: \(supportedCodes.joined(separator: ", "))."
        case .englishSourceRequired:
            "Canary 1B requires English in Primary or Additional for ASR."
        case .translationUnsupported(let modelID):
            "The local model \(modelID) does not support this translation operation."
        case .unsupportedOperation(let modelID):
            "The requested operation is unavailable for local model \(modelID)."
        case .engineIdentityMismatch(let modelID):
            "The selected engine no longer matches local model \(modelID)."
        }
    }
}

/// The immutable source of truth for one transcription session. The model,
/// backend, engine identity, HUD state and request fields are captured as one
/// value so a settings change during recording can only affect the next plan.
public struct TranscriptionSessionPlan: Equatable, Sendable {
    public let model: TranscriptionModelDescriptor
    public let modelID: String
    public let backend: TranscriptionModelDescriptor.Backend
    public let capabilities: ASRModelCapabilities
    public let modelFolderURL: URL
    public let engineIdentity: String
    public let operation: TranscriptionSessionOperation
    public let languageMode: TranscriptionLanguageMode
    public let sourceLanguageChoices: [String]
    public let sourceLanguageCode: String?
    public let requestedLanguageCode: String
    public let hudLanguageLabel: String
    public let languageControlEnabled: Bool
    public let route: TranscriptionLanguageRoute
    public let request: TranscriptionRequest
    public let supportsNativeWhisperTranslation: Bool
    public let sourceLanguageWarning: TranscriptionSessionLanguageWarning?

    public var isWhisperTargetMode: Bool {
        if case .whisperTargetTranslation = operation {
            return true
        }
        return false
    }

    public func request(audioFileURL: URL?) -> TranscriptionRequest {
        TranscriptionRequest(
            audioFileURL: audioFileURL,
            forcedLanguageCode: request.forcedLanguageCode,
            translateToEnglish: request.translateToEnglish
        )
    }

    fileprivate init(
        model: TranscriptionModelDescriptor,
        modelFolderURL: URL,
        engineIdentity: String,
        operation: TranscriptionSessionOperation,
        languageMode: TranscriptionLanguageMode,
        sourceLanguageChoices: [String],
        sourceLanguageCode: String?,
        requestedLanguageCode: String,
        hudLanguageLabel: String,
        languageControlEnabled: Bool,
        route: TranscriptionLanguageRoute,
        supportsNativeWhisperTranslation: Bool,
        request: TranscriptionRequest,
        sourceLanguageWarning: TranscriptionSessionLanguageWarning? = nil
    ) {
        self.model = model
        self.modelID = model.id
        self.backend = model.backend
        self.capabilities = model.capabilities
        self.modelFolderURL = modelFolderURL
        self.engineIdentity = engineIdentity
        self.operation = operation
        self.languageMode = languageMode
        self.sourceLanguageChoices = sourceLanguageChoices
        self.sourceLanguageCode = sourceLanguageCode
        self.requestedLanguageCode = requestedLanguageCode
        self.hudLanguageLabel = hudLanguageLabel
        self.languageControlEnabled = languageControlEnabled
        self.route = route
        self.request = request
        self.supportsNativeWhisperTranslation = supportsNativeWhisperTranslation
        self.sourceLanguageWarning = sourceLanguageWarning
    }
}

public enum TranscriptionSessionResolution: Equatable, Sendable {
    case available(TranscriptionSessionPlan)
    case unavailable(TranscriptionSessionUnavailableReason)

    public var hudLanguageMode: TranscriptionLanguageMode {
        switch self {
        case .available(let plan):
            plan.languageMode
        case .unavailable:
            .unavailable
        }
    }
}

/// Pure capability-aware resolver for local transcription sessions.
public enum TranscriptionSessionResolver {
    public static func resolve(
        _ snapshot: TranscriptionSessionSnapshot
    ) -> TranscriptionSessionResolution {
        guard let activeModel = snapshot.activeModel else {
            return .unavailable(.noActiveModel)
        }

        var model = activeModel
        if let capabilities = snapshot.capabilities {
            model.capabilities = capabilities
        }

        if model.backend != .whisperKitCoreML,
           case .whisperTargetTranslation = snapshot.operation {
            return .unavailable(.translationUnsupported(modelID: model.id))
        }

        if let requiredOS = model.capabilities.minOSVersion,
           snapshot.availability.currentOSVersion < requiredOS {
            return .unavailable(
                .unsupportedOS(
                    modelID: model.id,
                    required: requiredOS,
                    current: snapshot.availability.currentOSVersion
                )
            )
        }

        guard snapshot.availability.hasCompleteModel else {
            return .unavailable(.incompleteModel(modelID: model.id))
        }

        guard !model.capabilities.supportsAutoLanguageDetect
                || model.backend == .whisperKitCoreML
                || model.backend == .fluidAudioCoreML
        else {
            return .unavailable(.invalidCapabilities(modelID: model.id))
        }

        let folderURL = snapshot.modelFolderURL
            ?? URL(fileURLWithPath: "/")
        let engineIdentity = normalizedEngineIdentity(
            snapshot.engineIdentity,
            model: model
        )

        switch model.backend {
        case .canaryCoreML:
            return resolveCanary(
                model: model,
                folderURL: folderURL,
                engineIdentity: engineIdentity,
                snapshot: snapshot
            )
        case .gigaAMCoreML:
            return resolveGigaAM(
                model: model,
                folderURL: folderURL,
                engineIdentity: engineIdentity,
                snapshot: snapshot
            )
        case .whisperKitCoreML, .fluidAudioCoreML:
            return resolveLegacyWhisperFamily(
                model: model,
                folderURL: folderURL,
                engineIdentity: engineIdentity,
                snapshot: snapshot
            )
        }
    }

    public static func resolve(
        activeModel: TranscriptionModelDescriptor?,
        modelFolderURL: URL? = nil,
        engineIdentity: String? = nil,
        capabilities: ASRModelCapabilities? = nil,
        currentOSVersion: ASRModelCapabilities.OSVersion,
        hasCompleteModel: Bool = true,
        primaryLanguageCode: String?,
        additionalLanguageCode: String?,
        operation: TranscriptionSessionOperation,
        legacyLanguageCode: String? = nil,
        sourceLanguageOverride: String? = nil
    ) -> TranscriptionSessionResolution {
        resolve(
            TranscriptionSessionSnapshot(
                activeModel: activeModel,
                modelFolderURL: modelFolderURL,
                engineIdentity: engineIdentity,
                capabilities: capabilities,
                availability: TranscriptionSessionAvailability(
                    currentOSVersion: currentOSVersion,
                    hasCompleteModel: hasCompleteModel
                ),
                primaryLanguageCode: primaryLanguageCode,
                additionalLanguageCode: additionalLanguageCode,
                operation: operation,
                legacyLanguageCode: legacyLanguageCode,
                sourceLanguageOverride: sourceLanguageOverride
            )
        )
    }

    /// Rebuilds only the route fields for an already-created Canary session.
    /// The model, engine identity, model folder, and configured source pair all
    /// remain frozen to the original plan; mutable stores are not consulted.
    public static func replacingCanarySource(
        in plan: TranscriptionSessionPlan,
        with sourceLanguageCode: String
    ) -> TranscriptionSessionResolution {
        guard plan.backend == .canaryCoreML else {
            return .unavailable(.unsupportedOperation(modelID: plan.modelID))
        }
        guard case .asr = plan.operation else {
            return .unavailable(.translationUnsupported(modelID: plan.modelID))
        }

        let supportedCodes = verifiedCanarySources(for: plan.model)
        let sourceCode = normalizedLanguageCode(sourceLanguageCode)
        guard !sourceCode.isEmpty,
              sourceCode != "auto",
              supportedCodes.contains(sourceCode)
        else {
            return .unavailable(
                .unsupportedSourceLanguage(
                    modelID: plan.modelID,
                    requestedCode: sourceCode,
                    supportedCodes: supportedCodes
                )
            )
        }

        let sourceChoices = plan.sourceLanguageChoices.filter { supportedCodes.contains($0) }
        guard !sourceChoices.isEmpty else {
            return .unavailable(.invalidCapabilities(modelID: plan.modelID))
        }

        let route = TranscriptionLanguageRoute(
            forcedLanguageCode: sourceCode,
            translateToEnglish: false,
            postASRTextTranslationTargetLanguageCode: nil
        )
        return .available(
            makePlan(
                model: plan.model,
                folderURL: plan.modelFolderURL,
                engineIdentity: plan.engineIdentity,
                operation: plan.operation,
                languageMode: sourceChoices.count > 1 ? .switchable : .fixed,
                sourceChoices: sourceChoices,
                sourceCode: sourceCode,
                requestedLanguageCode: sourceCode,
                hudLanguageLabel: TranscriptionLanguageOption.hudLabel(for: sourceCode),
                languageControlEnabled: sourceChoices.count > 1,
                route: route,
                sourceLanguageWarning: plan.sourceLanguageWarning
            )
        )
    }

    private static func resolveCanary(
        model: TranscriptionModelDescriptor,
        folderURL: URL,
        engineIdentity: String,
        snapshot: TranscriptionSessionSnapshot
    ) -> TranscriptionSessionResolution {
        guard case .asr = snapshot.operation else {
            return .unavailable(.translationUnsupported(modelID: model.id))
        }

        let supportedCodes = verifiedCanarySources(for: model)
        guard !supportedCodes.isEmpty else {
            return .unavailable(.invalidCapabilities(modelID: model.id))
        }

        guard let primaryLanguageCode = normalizedOptionalLanguageCode(snapshot.primaryLanguageCode) else {
            return .unavailable(
                .noSupportedSource(modelID: model.id, supportedCodes: supportedCodes)
            )
        }

        guard supportedCodes.contains(primaryLanguageCode) else {
            return .unavailable(
                .unsupportedSourceLanguage(
                    modelID: model.id,
                    requestedCode: primaryLanguageCode,
                    supportedCodes: supportedCodes
                )
            )
        }

        let sourceChoices = normalizedPair(
            primary: primaryLanguageCode,
            additional: snapshot.additionalLanguageCode
        ).filter { supportedCodes.contains($0) }
        let sourceLanguageCode: String
        if let rawOverride = snapshot.sourceLanguageOverride {
            let override = normalizedLanguageCode(rawOverride)
            guard !override.isEmpty,
                  override != "auto",
                  supportedCodes.contains(override)
            else {
                return .unavailable(
                    .unsupportedSourceLanguage(
                        modelID: model.id,
                        requestedCode: override,
                        supportedCodes: supportedCodes
                    )
                )
            }
            sourceLanguageCode = override
        } else {
            sourceLanguageCode = primaryLanguageCode
        }

        let route = TranscriptionLanguageRoute(
            forcedLanguageCode: sourceLanguageCode,
            translateToEnglish: false,
            postASRTextTranslationTargetLanguageCode: nil
        )
        return .available(
            makePlan(
                model: model,
                folderURL: folderURL,
                engineIdentity: engineIdentity,
                operation: snapshot.operation,
                languageMode: sourceChoices.count > 1 ? .switchable : .fixed,
                sourceChoices: sourceChoices,
                sourceCode: sourceLanguageCode,
                requestedLanguageCode: sourceLanguageCode,
                hudLanguageLabel: TranscriptionLanguageOption.hudLabel(for: sourceLanguageCode),
                languageControlEnabled: sourceChoices.count > 1,
                route: route,
                sourceLanguageWarning: nil
            )
        )
    }

    private static func resolveGigaAM(
        model: TranscriptionModelDescriptor,
        folderURL: URL,
        engineIdentity: String,
        snapshot: TranscriptionSessionSnapshot
    ) -> TranscriptionSessionResolution {
        guard case .asr = snapshot.operation else {
            return .unavailable(.translationUnsupported(modelID: model.id))
        }

        guard verifiedGigaAMSources(for: model).contains("ru") else {
            return .unavailable(.invalidCapabilities(modelID: model.id))
        }

        if let rawOverride = snapshot.sourceLanguageOverride {
            let override = normalizedLanguageCode(rawOverride)
            guard override == "ru" else {
                return .unavailable(
                    .unsupportedSourceLanguage(
                        modelID: model.id,
                        requestedCode: override,
                        supportedCodes: ["ru"]
                    )
                )
            }
        }

        let route = TranscriptionLanguageRoute(
            forcedLanguageCode: "ru",
            translateToEnglish: false,
            postASRTextTranslationTargetLanguageCode: nil
        )
        return .available(
            makePlan(
                model: model,
                folderURL: folderURL,
                engineIdentity: engineIdentity,
                operation: snapshot.operation,
                languageMode: .fixed,
                sourceChoices: ["ru"],
                sourceCode: "ru",
                requestedLanguageCode: "ru",
                hudLanguageLabel: TranscriptionLanguageOption.hudLabel(for: "ru"),
                languageControlEnabled: false,
                route: route
            )
        )
    }

    private static func resolveLegacyWhisperFamily(
        model: TranscriptionModelDescriptor,
        folderURL: URL,
        engineIdentity: String,
        snapshot: TranscriptionSessionSnapshot
    ) -> TranscriptionSessionResolution {
        let languageCode = normalizedLanguageCode(snapshot.legacyLanguageCode ?? "auto")
        let isMultilingual = model.backend == .whisperKitCoreML
            && model.languageSupport == .multilingual
        let route: TranscriptionLanguageRoute
        let languageMode: TranscriptionLanguageMode
        let requestedLanguageCode: String
        let hudLabel: String

        if model.backend == .fluidAudioCoreML,
           case .whisperTargetTranslation = snapshot.operation {
            return .unavailable(.translationUnsupported(modelID: model.id))
        }

        switch snapshot.operation {
        case .asr:
            // Parakeet must not inherit a restrictive Whisper preference. It
            // auto-detects internally even when the legacy setting is explicit.
            route = model.backend == .fluidAudioCoreML
                ? TranscriptionLanguageRoute(
                    forcedLanguageCode: nil,
                    translateToEnglish: false,
                    postASRTextTranslationTargetLanguageCode: nil
                )
                : TranscriptionLanguageRouter.route(
                    resolvedLanguageCode: languageCode,
                    isMultilingualModel: isMultilingual
                )
            languageMode = .auto
            requestedLanguageCode = languageCode
            hudLabel = TranscriptionLanguageOption.hudLabel(for: languageCode)
        case .whisperTargetTranslation(let targetCode):
            route = TranscriptionLanguageRouter.route(
                resolvedLanguageCode: normalizedLanguageCode(targetCode),
                isMultilingualModel: isMultilingual,
                forceTargetLanguage: true
            )
            languageMode = .target
            requestedLanguageCode = normalizedLanguageCode(targetCode)
            hudLabel = TranscriptionLanguageOption.hudLabel(for: requestedLanguageCode)
        }

        return .available(
            makePlan(
                model: model,
                folderURL: folderURL,
                engineIdentity: engineIdentity,
                operation: snapshot.operation,
                languageMode: languageMode,
                sourceChoices: [],
                sourceCode: route.forcedLanguageCode,
                requestedLanguageCode: requestedLanguageCode,
                hudLanguageLabel: hudLabel,
                languageControlEnabled: true,
                route: route
            )
        )
    }

    private static func makePlan(
        model: TranscriptionModelDescriptor,
        folderURL: URL,
        engineIdentity: String,
        operation: TranscriptionSessionOperation,
        languageMode: TranscriptionLanguageMode,
        sourceChoices: [String],
        sourceCode: String?,
        requestedLanguageCode: String,
        hudLanguageLabel: String,
        languageControlEnabled: Bool,
        route: TranscriptionLanguageRoute,
        sourceLanguageWarning: TranscriptionSessionLanguageWarning? = nil
    ) -> TranscriptionSessionPlan {
        TranscriptionSessionPlan(
            model: model,
            modelFolderURL: folderURL,
            engineIdentity: engineIdentity,
            operation: operation,
            languageMode: languageMode,
            sourceLanguageChoices: sourceChoices,
            sourceLanguageCode: sourceCode,
            requestedLanguageCode: requestedLanguageCode,
            hudLanguageLabel: hudLanguageLabel,
            languageControlEnabled: languageControlEnabled,
            route: route,
            supportsNativeWhisperTranslation: model.backend == .whisperKitCoreML
                && model.languageSupport == .multilingual,
            request: TranscriptionRequest(
                forcedLanguageCode: route.forcedLanguageCode,
                translateToEnglish: route.translateToEnglish
            ),
            sourceLanguageWarning: sourceLanguageWarning
        )
    }

    private static func verifiedCanarySources(
        for model: TranscriptionModelDescriptor
    ) -> [String] {
        model.capabilities.explicitSupportedLanguageCodes
    }

    private static func verifiedGigaAMSources(
        for model: TranscriptionModelDescriptor
    ) -> [String] {
        model.capabilities.explicitSupportedLanguageCodes.filter { $0 == "ru" }
    }

    private static func normalizedPair(
        primary: String?,
        additional: String?
    ) -> [String] {
        var seen = Set<String>()
        return [primary, additional].compactMap { rawCode in
            guard let rawCode else { return nil }
            let code = normalizedLanguageCode(rawCode)
            guard !code.isEmpty, code != "auto", seen.insert(code).inserted else {
                return nil
            }
            return code
        }
    }

    private static func normalizedLanguageCode(_ rawCode: String) -> String {
        rawCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedOptionalLanguageCode(_ rawCode: String?) -> String? {
        guard let rawCode else { return nil }
        let code = normalizedLanguageCode(rawCode)
        return code.isEmpty || code == "auto" ? nil : code
    }

    private static func normalizedEngineIdentity(
        _ identity: String?,
        model: TranscriptionModelDescriptor
    ) -> String {
        let normalized = identity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalized.isEmpty else {
            return "\(model.backend.rawValue):\(model.id)"
        }
        return normalized
    }
}

public enum TranscriptionLanguageRouter {
    public static func route(
        resolvedLanguageCode: String,
        isMultilingualModel: Bool,
        forceTargetLanguage: Bool = false
    ) -> TranscriptionLanguageRoute {
        let languageCode = resolvedLanguageCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if forceTargetLanguage {
            let targetCode = normalizedTargetCode(languageCode)
            // Whisper can natively translate only to English (`task: .translate`).
            // For any other target language we always need a post-transcription
            // LLM pass — the language token is a *source* language constraint,
            // not an output-language selector.
            if isEnglishTarget(targetCode) {
                if isMultilingualModel {
                    return TranscriptionLanguageRoute(
                        forcedLanguageCode: nil,
                        translateToEnglish: true,
                        postASRTextTranslationTargetLanguageCode: nil
                    )
                }
                // English-only Whisper models cannot translate; fall back to LLM.
                return TranscriptionLanguageRoute(
                    forcedLanguageCode: nil,
                    translateToEnglish: false,
                    postASRTextTranslationTargetLanguageCode: targetCode
                )
            }

            return TranscriptionLanguageRoute(
                forcedLanguageCode: nil,
                translateToEnglish: false,
                postASRTextTranslationTargetLanguageCode: targetCode
            )
        }

        guard !languageCode.isEmpty, languageCode != "auto" else {
            return TranscriptionLanguageRoute(
                forcedLanguageCode: nil,
                translateToEnglish: false,
                postASRTextTranslationTargetLanguageCode: nil
            )
        }

        guard isMultilingualModel else {
            return TranscriptionLanguageRoute(
                forcedLanguageCode: languageCode,
                translateToEnglish: false,
                postASRTextTranslationTargetLanguageCode: nil
            )
        }

        return TranscriptionLanguageRoute(
            forcedLanguageCode: languageCode,
            translateToEnglish: false,
            postASRTextTranslationTargetLanguageCode: nil
        )
    }

    private static func normalizedTargetCode(_ languageCode: String) -> String {
        if languageCode.isEmpty || languageCode == "auto" {
            return "en"
        }
        if languageCode == "english" {
            return "en"
        }
        return languageCode
    }

    private static func isEnglishTarget(_ targetCode: String) -> Bool {
        targetCode == "en" || targetCode.hasPrefix("en-") || targetCode == "english"
    }
}

/// A language option presented by the transient HUD menu.
public struct HUDLanguageMenuOption: Identifiable, Equatable, Sendable {
    public let code: String
    public let displayName: String
    public let hudLabel: String
    public let isCurrent: Bool
    public let isSelectable: Bool

    public var id: String { code }

    public init(
        code: String,
        displayName: String,
        hudLabel: String,
        isCurrent: Bool,
        isSelectable: Bool
    ) {
        self.code = code
        self.displayName = displayName
        self.hudLabel = hudLabel
        self.isCurrent = isCurrent
        self.isSelectable = isSelectable
    }
}

/// Pure language-menu policy shared by the HUD's left control.
public enum HUDLanguageMenuPolicy {
    /// The purpose of the language picker.
    public enum PickerPurpose: Equatable, Sendable {
        /// Explicit ASR source picker for Canary/GigaAM models.
        /// Shows verified source languages only, no Auto.
        case explicitASRSource
        /// Target language picker for Whisper/Cloud/Auto.
        /// Shows Auto + complete 25-language target catalog.
        case targetLanguageSelection
    }

    /// Preserves the Settings pair order while removing duplicate/empty values.
    public static func configuredCodes(from languages: UserSpeechLanguages) -> [String] {
        languages.orderedDistinctCodes
    }

    /// Builds explicit source choices from the configured pair and the active
    /// model's verified source capabilities.
    public static func canarySourceCodes(
        primary: String?,
        additional: String?,
        supportedCodes: [String]
    ) -> [String] {
        let supported = Set(normalizedDistinctCodes(supportedCodes))
        return normalizedDistinctCodes([primary, additional].compactMap { $0 })
            .filter { supported.contains($0) }
    }

    /// Returns the complete 25-language target catalog (Canary 1B language set).
    public static var completeTargetCatalog: [String] {
        CanaryLanguageCatalog.oneBV2LanguageCodes
    }

    /// Returns Canary Flash's 4-language source catalog.
    public static var flashSourceCatalog: [String] {
        CanaryLanguageCatalog.flashLanguageCodes
    }

    /// Cycles only genuinely switchable explicit choices. A fixed source returns
    /// nil so a left click cannot imply a language change that did not happen.
    public static func nextCode(current: String, choices: [String]) -> String? {
        guard choices.count > 1 else { return nil }
        guard let currentIndex = choices.firstIndex(of: normalized(current)) else {
            return choices[0]
        }
        return choices[(currentIndex + 1) % choices.count]
    }

    /// Creates menu options for the active backend and picker purpose.
    public static func options(
        backend: TranscriptionModelDescriptor.Backend?,
        languages: UserSpeechLanguages,
        supportedSourceCodes: [String] = [],
        currentCode: String?,
        isAutomatic: Bool,
        uiLanguage: UILanguagePreference,
        systemLocale: Locale = .current,
        purpose: PickerPurpose = .explicitASRSource
    ) -> [HUDLanguageMenuOption] {
        let effectiveBackend = backend ?? .whisperKitCoreML
        let codes: [String]
        let includesAutomatic: Bool
        switch (effectiveBackend, purpose) {
        case (.canaryCoreML, .explicitASRSource):
            codes = normalizedDistinctCodes(supportedSourceCodes)
            includesAutomatic = false
        case (.canaryCoreML, .targetLanguageSelection):
            codes = completeTargetCatalog
            includesAutomatic = true
        case (.gigaAMCoreML, _):
            codes = ["ru"]
            includesAutomatic = false
        case (.whisperKitCoreML, .explicitASRSource), (.fluidAudioCoreML, .explicitASRSource):
            codes = normalizedDistinctCodes(supportedSourceCodes)
            includesAutomatic = false
        case (.whisperKitCoreML, .targetLanguageSelection), (.fluidAudioCoreML, .targetLanguageSelection):
            codes = completeTargetCatalog
            includesAutomatic = true
        }

        let selectable: Bool
        switch (effectiveBackend, purpose) {
        case (.canaryCoreML, .explicitASRSource):
            selectable = codes.count > 1
        case (.canaryCoreML, .targetLanguageSelection), (.whisperKitCoreML, .targetLanguageSelection), (.fluidAudioCoreML, .targetLanguageSelection):
            selectable = true
        case (.gigaAMCoreML, _):
            selectable = false
        case (.whisperKitCoreML, .explicitASRSource), (.fluidAudioCoreML, .explicitASRSource):
            selectable = codes.count > 1
        }

        let automaticOption = includesAutomatic
            ? [HUDLanguageMenuOption(
                code: "auto",
                displayName: AppText.localized(.autoDetect, language: uiLanguage, systemLocale: systemLocale),
                hudLabel: "A",
                isCurrent: isAutomatic,
                isSelectable: true
            )]
            : []

        return automaticOption + codes.map { code in
            HUDLanguageMenuOption(
                code: code,
                displayName: HUDQuickSwitcherLayout.localizedSpeechLanguageName(
                    for: code,
                    language: uiLanguage,
                    systemLocale: systemLocale
                ),
                hudLabel: TranscriptionLanguageOption.hudLabel(for: code),
                isCurrent: !isAutomatic && normalized(code) == normalized(currentCode ?? ""),
                isSelectable: selectable
            )
        }
    }

    private static func normalizedDistinctCodes(_ codes: [String]) -> [String] {
        var seen = Set<String>()
        return codes.compactMap { rawCode in
            let code = normalized(rawCode)
            guard !code.isEmpty, code != "auto", seen.insert(code).inserted else { return nil }
            return code
        }
    }

    private static func normalized(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
