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

    public init(
        activeModel: TranscriptionModelDescriptor?,
        modelFolderURL: URL? = nil,
        engineIdentity: String? = nil,
        capabilities: ASRModelCapabilities? = nil,
        availability: TranscriptionSessionAvailability,
        primaryLanguageCode: String?,
        additionalLanguageCode: String?,
        operation: TranscriptionSessionOperation,
        legacyLanguageCode: String? = nil
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
        legacyLanguageCode: String? = nil
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
                legacyLanguageCode: legacyLanguageCode
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

        let route = TranscriptionLanguageRoute(
            forcedLanguageCode: primaryLanguageCode,
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
                sourceChoices: [primaryLanguageCode],
                sourceCode: primaryLanguageCode,
                requestedLanguageCode: primaryLanguageCode,
                hudLanguageLabel: TranscriptionLanguageOption.hudLabel(for: primaryLanguageCode),
                languageControlEnabled: false,
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
