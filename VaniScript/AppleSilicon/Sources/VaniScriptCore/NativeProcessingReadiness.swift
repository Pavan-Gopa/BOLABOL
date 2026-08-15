import Foundation

/// A user-facing language choice backed by one canonical ASR/translation code.
public struct NativeLanguageOption: Identifiable, Equatable, Sendable {
    public let code: String
    public let displayName: String

    public var id: String { code }

    public init(code: String, displayName: String) {
        self.code = code
        self.displayName = displayName
    }
}

/// Canonical language normalization shared by configuration, readiness,
/// transcription, and translation decisions.
public enum NativeLanguagePolicy {
    public static let autoCode = "auto"
    public static let keepOriginalCode = "same"
    public static let chooseSourceCode = "__choose_source__"

    public static let targetLanguageOptions: [NativeLanguageOption] = [
        NativeLanguageOption(code: keepOriginalCode, displayName: "Keep Original"),
        NativeLanguageOption(code: "ru", displayName: "Russian"),
        NativeLanguageOption(code: "cs", displayName: "Czech"),
        NativeLanguageOption(code: "fr", displayName: "French"),
        NativeLanguageOption(code: "de", displayName: "German"),
        NativeLanguageOption(code: "pl", displayName: "Polish"),
        NativeLanguageOption(code: "en", displayName: "English"),
        NativeLanguageOption(code: "hi", displayName: "Hindi"),
        NativeLanguageOption(code: "es", displayName: "Spanish"),
        NativeLanguageOption(code: "sv", displayName: "Swedish"),
        NativeLanguageOption(code: "it", displayName: "Italian"),
        NativeLanguageOption(code: "pt", displayName: "Portuguese"),
        NativeLanguageOption(code: "nl", displayName: "Dutch"),
        NativeLanguageOption(code: "af", displayName: "Afrikaans"),
        NativeLanguageOption(code: "bn", displayName: "Bengali"),
        NativeLanguageOption(code: "bg", displayName: "Bulgarian"),
        NativeLanguageOption(code: "hr", displayName: "Croatian"),
        NativeLanguageOption(code: "el", displayName: "Greek"),
        NativeLanguageOption(code: "gu", displayName: "Gujarati"),
        NativeLanguageOption(code: "hu", displayName: "Hungarian"),
        NativeLanguageOption(code: "ko", displayName: "Korean"),
        NativeLanguageOption(code: "no", displayName: "Norwegian"),
        NativeLanguageOption(code: "ro", displayName: "Romanian"),
        NativeLanguageOption(code: "sk", displayName: "Slovak"),
        NativeLanguageOption(code: "sl", displayName: "Slovenian"),
        NativeLanguageOption(code: "te", displayName: "Telugu"),
        NativeLanguageOption(code: "uk", displayName: "Ukrainian"),
        NativeLanguageOption(code: "yo", displayName: "Yoruba")
    ]

    public static func canonicalCode(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return autoCode }
        if let code = aliases[normalized] {
            return code
        }
        if let base = normalized.split(whereSeparator: { $0 == "-" || $0 == "_" }).first,
           base.count == 2,
           let code = aliases[String(base)] {
            return code
        }
        return normalized
    }

    public static func displayName(for value: String) -> String {
        let code = canonicalCode(value)
        if code == autoCode { return "Auto Detect" }
        if code == keepOriginalCode { return "Keep Original" }
        if let displayName = languageNames[code] { return displayName }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "Auto Detect" }
        return clean.prefix(1).uppercased() + clean.dropFirst()
    }

    /// Converts aliases to the stable values persisted by the current UI.
    public static func storageValue(for value: String) -> String {
        let code = canonicalCode(value)
        if code == autoCode { return autoCode }
        if code == keepOriginalCode { return keepOriginalCode }
        return languageNames[code] ?? value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func sourceLanguageOptions(
        for descriptor: LocalASRModelDescriptor?
    ) -> [NativeLanguageOption] {
        let supportsAuto = descriptor?.capabilities.supportsAutoLanguageDetect ?? true
        let codes = descriptor?.capabilities.supportedLanguageCodes
            ?? targetLanguageOptions.map(\.code)
        var options: [NativeLanguageOption] = []
        if supportsAuto {
            options.append(NativeLanguageOption(code: autoCode, displayName: "Auto Detect"))
        }
        for rawCode in codes {
            let code = canonicalCode(rawCode)
            guard code != autoCode,
                  code != keepOriginalCode,
                  languageNames[code] != nil,
                  !options.contains(where: { $0.code == code })
            else {
                continue
            }
            options.append(NativeLanguageOption(code: code, displayName: displayName(for: code)))
        }
        return options
    }

    public static func supportsSourceLanguage(
        _ value: String,
        descriptor: LocalASRModelDescriptor
    ) -> Bool {
        descriptor.capabilities.supportsSourceLanguage(canonicalCode(value))
    }

    public static func translationNeeded(sourceLang: String, targetLang: String) -> Bool {
        let targetCode = canonicalCode(targetLang)
        guard targetCode != keepOriginalCode else { return false }
        return canonicalCode(sourceLang) != targetCode
    }

    private static let languageNames: [String: String] = [
        "af": "Afrikaans",
        "bg": "Bulgarian",
        "bn": "Bengali",
        "hr": "Croatian",
        "cs": "Czech",
        "da": "Danish",
        "nl": "Dutch",
        "en": "English",
        "et": "Estonian",
        "fi": "Finnish",
        "fr": "French",
        "de": "German",
        "el": "Greek",
        "gu": "Gujarati",
        "hi": "Hindi",
        "hu": "Hungarian",
        "it": "Italian",
        "ko": "Korean",
        "lv": "Latvian",
        "lt": "Lithuanian",
        "mt": "Maltese",
        "no": "Norwegian",
        "pl": "Polish",
        "pt": "Portuguese",
        "ro": "Romanian",
        "sk": "Slovak",
        "sl": "Slovenian",
        "es": "Spanish",
        "sv": "Swedish",
        "ru": "Russian",
        "te": "Telugu",
        "uk": "Ukrainian",
        "yo": "Yoruba"
    ]

    private static let aliases: [String: String] = [
        "auto": autoCode,
        "automatic": autoCode,
        "automatic detection": autoCode,
        "auto detect": autoCode,
        "same": keepOriginalCode,
        "keep original": keepOriginalCode,
        "keep original (same)": keepOriginalCode,
        "keeporiginal": keepOriginalCode,
        "af": "af", "afr": "af", "afrikaans": "af",
        "bg": "bg", "bul": "bg", "bulgarian": "bg",
        "bn": "bn", "ben": "bn", "bengali": "bn",
        "hr": "hr", "hrv": "hr", "croatian": "hr",
        "cs": "cs", "cz": "cs", "ces": "cs", "czech": "cs",
        "da": "da", "dan": "da", "danish": "da",
        "nl": "nl", "nld": "nl", "dutch": "nl",
        "en": "en", "eng": "en", "english": "en",
        "et": "et", "est": "et", "estonian": "et",
        "fi": "fi", "fin": "fi", "finnish": "fi",
        "fr": "fr", "fra": "fr", "fre": "fr", "french": "fr",
        "de": "de", "deu": "de", "ger": "de", "german": "de",
        "el": "el", "ell": "el", "gre": "el", "greek": "el",
        "gu": "gu", "guj": "gu", "gujarati": "gu",
        "hi": "hi", "hin": "hi", "hindi": "hi",
        "hu": "hu", "hun": "hu", "hungarian": "hu",
        "it": "it", "ita": "it", "italian": "it",
        "ko": "ko", "kor": "ko", "korean": "ko",
        "lv": "lv", "lav": "lv", "latvian": "lv",
        "lt": "lt", "lit": "lt", "lithuanian": "lt",
        "mt": "mt", "mlt": "mt", "maltese": "mt",
        "no": "no", "nor": "no", "norwegian": "no",
        "pl": "pl", "pol": "pl", "polish": "pl",
        "pt": "pt", "por": "pt", "portuguese": "pt",
        "ro": "ro", "ron": "ro", "rum": "ro", "romanian": "ro",
        "sk": "sk", "slk": "sk", "slo": "sk", "slovak": "sk",
        "sl": "sl", "slv": "sl", "slovenian": "sl",
        "es": "es", "spa": "es", "spanish": "es",
        "sv": "sv", "swe": "sv", "swedish": "sv",
        "ru": "ru", "rus": "ru", "russian": "ru",
        "te": "te", "tel": "te", "telugu": "te",
        "uk": "uk", "ukr": "uk", "ukrainian": "uk",
        "yo": "yo", "yor": "yo", "yoruba": "yo"
    ]
}
public struct NativeProcessingReadinessResult: Codable, Equatable, Sendable {
    public var canTranscribe: Bool
    public var canTranslate: Bool
    public var transcriptionMessage: String
    public var translationMessage: String
}

public enum NativeProcessingReadiness {
    public static func evaluate(
        settings: AppSettings,
        sourceLang: String,
        targetLang: String,
        transcriptionProvider: String,
        translationProvider: String,
        onMacOSMajor: Int? = nil,
        fileManager: FileManager = .default
    ) -> NativeProcessingReadinessResult {
        let transcriptionReadiness: (ready: Bool, message: String)

        if let descriptor = NativeModelCatalog.descriptor(for: transcriptionProvider) {
            transcriptionReadiness = localTranscriptionReadiness(
                descriptor: descriptor,
                settings: settings,
                sourceLang: sourceLang,
                onMacOSMajor: onMacOSMajor,
                fileManager: fileManager
            )
        } else if transcriptionProvider == "coreml-whisperkit" {
            transcriptionReadiness = whisperKitAliasReadiness(
                settings: settings,
                sourceLang: sourceLang,
                onMacOSMajor: onMacOSMajor,
                fileManager: fileManager
            )
        } else {
            let transcriptionOption = ProviderRegistry
                .availableTranscriptionProviders(settings: settings)
                .first { $0.id == transcriptionProvider }
            if let transcriptionOption, transcriptionOption.group == .cloud {
                transcriptionReadiness = (
                    ready: true,
                    message: "\(transcriptionOption.label) transcription ready."
                )
            } else {
                transcriptionReadiness = (
                    ready: false,
                    message: "Transcription provider '\(transcriptionProvider)' is unavailable."
                )
            }
        }

        let translationNeeded = NativeLanguagePolicy.translationNeeded(
            sourceLang: sourceLang,
            targetLang: targetLang
        )
        let translationOption: ProviderOption?
        if translationNeeded {
            translationOption = ProviderRegistry
                .availableTranslationProviders(settings: settings, targetLang: targetLang)
                .providers
                .first { $0.id == translationProvider }
        } else {
            translationOption = nil
        }
        let cloudTranslationReady = translationOption?.group == .cloud
        let localTranslationReady = translationNeeded
            && NativeModelCatalog.activeMLXModel(
                settings: settings,
                providerID: translationProvider
            ) != nil
        let translationReady = !translationNeeded || cloudTranslationReady || localTranslationReady

        let translationMessage: String
        if !translationNeeded {
            translationMessage = "Translation disabled for same-language sessions."
        } else if let translationOption, translationOption.group == .cloud {
            translationMessage = "\(translationOption.label) translation ready."
        } else if localTranslationReady {
            translationMessage = "MLX translation model ready."
        } else {
            translationMessage = "MLX translation requires a downloaded or located local model."
        }

        return NativeProcessingReadinessResult(
            canTranscribe: transcriptionReadiness.ready,
            canTranslate: translationReady,
            transcriptionMessage: transcriptionReadiness.message,
            translationMessage: translationMessage
        )
    }

    private static func localTranscriptionReadiness(
        descriptor: LocalASRModelDescriptor,
        settings: AppSettings,
        sourceLang: String,
        onMacOSMajor: Int?,
        fileManager: FileManager
    ) -> (ready: Bool, message: String) {
        let currentMacOSMajor = onMacOSMajor ?? ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        if !descriptor.capabilities.isAvailable(onMacOSMajor: currentMacOSMajor) {
            let requiredMajor = descriptor.capabilities.minimumMacOSMajor ?? currentMacOSMajor
            return (
                ready: false,
                message: "\(descriptor.displayName) requires macOS \(requiredMajor) or later (current: macOS \(currentMacOSMajor))."
            )
        }

        let sourceLanguageCode = NativeLanguagePolicy.canonicalCode(sourceLang)
        guard descriptor.capabilities.supportsSourceLanguage(sourceLanguageCode) else {
            if sourceLanguageCode == NativeLanguagePolicy.autoCode {
                return (
                    ready: false,
                    message: "\(descriptor.displayName) requires an explicit source language (supported: \(supportedLanguageList(for: descriptor)))."
                )
            }
            let input = sourceLang.trimmingCharacters(in: .whitespacesAndNewlines)
            return (
                ready: false,
                message: "\(descriptor.displayName) does not support source language '\(input.isEmpty ? "auto" : input)' (supported: \(supportedLanguageList(for: descriptor)))."
            )
        }

        guard let model = settings.localAsrModels[descriptor.id] else {
            return missingLocalModelReadiness(for: descriptor)
        }
        if model.status == .failed {
            return incompleteLocalModelReadiness(for: descriptor)
        }
        guard model.status == .downloaded else {
            return missingLocalModelReadiness(for: descriptor)
        }
        guard model.runtime == descriptor.settingsRuntime else {
            return incompleteLocalModelReadiness(for: descriptor)
        }
        guard let path = model.path, !path.isEmpty else {
            return missingLocalModelReadiness(for: descriptor)
        }
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return missingLocalModelReadiness(for: descriptor)
        }

        guard NativeModelCatalog.activeLocalASRModel(
            settings: settings,
            providerID: descriptor.id,
            onMacOSMajor: currentMacOSMajor,
            fileManager: fileManager
        ) != nil else {
            return incompleteLocalModelReadiness(for: descriptor)
        }

        return readyLocalModelReadiness(for: descriptor)
    }

    private static func whisperKitAliasReadiness(
        settings: AppSettings,
        sourceLang: String,
        onMacOSMajor: Int?,
        fileManager: FileManager
    ) -> (ready: Bool, message: String) {
        let currentMacOSMajor = onMacOSMajor ?? ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        guard let activeModel = NativeModelCatalog.activeLocalASRModel(
            settings: settings,
            providerID: "coreml-whisperkit",
            onMacOSMajor: currentMacOSMajor,
            fileManager: fileManager
        ) else {
            return (
                ready: false,
                message: "Core ML transcription requires a downloaded or located WhisperKit model."
            )
        }

        let sourceLanguageCode = NativeLanguagePolicy.canonicalCode(sourceLang)
        guard activeModel.descriptor.capabilities.supportsSourceLanguage(sourceLanguageCode) else {
            if sourceLanguageCode == NativeLanguagePolicy.autoCode {
                return (
                    ready: false,
                    message: "\(activeModel.descriptor.displayName) requires an explicit source language (supported: \(supportedLanguageList(for: activeModel.descriptor)))."
                )
            }
            let input = sourceLang.trimmingCharacters(in: .whitespacesAndNewlines)
            return (
                ready: false,
                message: "\(activeModel.descriptor.displayName) does not support source language '\(input.isEmpty ? "auto" : input)' (supported: \(supportedLanguageList(for: activeModel.descriptor)))."
            )
        }

        return (ready: true, message: "Core ML transcription model ready.")
    }

    private static func readyLocalModelReadiness(
        for descriptor: LocalASRModelDescriptor
    ) -> (ready: Bool, message: String) {
        (ready: true, message: "\(descriptor.displayName) ready.")
    }

    private static func missingLocalModelReadiness(
        for descriptor: LocalASRModelDescriptor
    ) -> (ready: Bool, message: String) {
        (
            ready: false,
            message: "\(descriptor.displayName) requires a downloaded or located local model."
        )
    }

    private static func incompleteLocalModelReadiness(
        for descriptor: LocalASRModelDescriptor
    ) -> (ready: Bool, message: String) {
        (
            ready: false,
            message: "\(descriptor.displayName) model files are incomplete or failed integrity validation."
        )
    }

    private static func supportedLanguageList(
        for descriptor: LocalASRModelDescriptor
    ) -> String {
        descriptor.capabilities.supportedLanguageCodes.joined(separator: ", ")
    }
}
