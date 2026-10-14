import Foundation

/// ADR-029/Q3a: a wrong-language result after the strict retry keeps the
/// polished source-language text (translation failure, not polishing
/// failure). The output pipeline translates it — or falls back to it with a
/// signal — instead of dropping it for Raw.

/// Q5a: cloud engines whose key chain must respect the output-language chain
/// cap. The workflow passes the chain deadline through this overload (first
/// pass and strict retry); the engine must not start a new key at/after it.
public protocol DeadlineAwarePolishingEngine: PolishingEngine {
    func polish(
        _ request: PolishingRequest,
        keyChainSeconds: TimeInterval,
        deadline: Date?
    ) async throws -> PolishingResult
}

@MainActor
public final class PolishingWorkflow {
    private let noteStore: NoteStore
    private let engine: any PolishingEngine
    private let templateProvider: (ProcessingVariant) -> PromptTemplate
    private let messageProvider: (AppTextKey) -> String
    private let humorLevel: HumorLevel?
    private let humorPromptMode: HumorPromptMode

    public init(
        noteStore: NoteStore,
        engine: any PolishingEngine,
        templateProvider: @escaping (ProcessingVariant) -> PromptTemplate = {
            .defaultTemplate(for: $0)
        },
        messageProvider: @escaping (AppTextKey) -> String = {
            AppText.localized($0, language: .english)
        },
        humorLevel: HumorLevel? = nil,
        humorPromptMode: HumorPromptMode = .playful
    ) {
        self.noteStore = noteStore
        self.engine = engine
        self.templateProvider = templateProvider
        self.messageProvider = messageProvider
        self.humorLevel = humorLevel
        self.humorPromptMode = humorPromptMode
    }

    /// Shared production construction seam for every user-facing polish path.
    /// Humor is enabled only when the HUD/Settings slider is enabled; the
    /// workflow itself still limits the transient block to Variant 2.
    public static func make(
        noteStore: NoteStore,
        engine: any PolishingEngine,
        templateProvider: @escaping (ProcessingVariant) -> PromptTemplate = {
            .defaultTemplate(for: $0)
        },
        messageProvider: @escaping (AppTextKey) -> String = {
            AppText.localized($0, language: .english)
        },
        humorSliderEnabled: Bool,
        humorLevel: HumorLevel,
        humorPromptMode: HumorPromptMode
    ) -> PolishingWorkflow {
        PolishingWorkflow(
            noteStore: noteStore,
            engine: engine,
            templateProvider: templateProvider,
            messageProvider: messageProvider,
            humorLevel: humorSliderEnabled ? humorLevel : nil,
            humorPromptMode: humorPromptMode
        )
    }

    @discardableResult
    public func polishNote(
        _ noteID: BolabolNote.ID,
        variants: [ProcessingVariant] = [.variantOne, .variantTwo],
        targetLanguage: String? = nil,
        primaryLanguageCode: String? = nil,
        additionalLanguageCode: String? = nil,
        deadline: Date? = nil
    ) async -> [ProcessingVariant: PolishingResult] {
        var results: [ProcessingVariant: PolishingResult] = [:]
        guard let note = noteStore.note(withID: noteID) else { return results }
        let rawText = note.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let languageGuard = PolishingLanguageGuard(
            sourceText: rawText,
            targetLanguage: targetLanguage,
            primaryLanguageCode: primaryLanguageCode,
            additionalLanguageCode: additionalLanguageCode
        )

        guard !rawText.isEmpty else {
            for variant in variants.polishableVariants {
                noteStore.markPolishingFailed(
                    for: noteID,
                    variant: variant,
                    message: messageProvider(.noTranscriptToPolish),
                    backendName: engine.displayName
                )
            }
            return results
        }

        for variant in variants.polishableVariants {
            // Q5a: never start new polish work at or after the chain cap.
            if let deadline, Date() >= deadline {
                noteStore.markPolishingFailed(
                    for: noteID,
                    variant: variant,
                    message: CloudKeyFailover.TimeoutError().localizedDescription,
                    backendName: engine.displayName
                )
                continue
            }
            noteStore.markPolishingStarted(
                for: noteID,
                variant: variant,
                backendName: engine.displayName
            )

            do {
                let result = try await polishWithLanguageGuard(
                    rawText: rawText,
                    variant: variant,
                    template: templateProvider(variant),
                    languageGuard: languageGuard,
                    deadline: deadline
                )
                guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    noteStore.markPolishingFailed(
                        for: noteID,
                        variant: variant,
                        message: messageProvider(.emptyPolishingResult),
                        backendName: result.diagnostics.backendName
                    )
                    continue
                }
                noteStore.applyPolishingResult(for: noteID, variant: variant, result: result)
                results[variant] = result
            } catch {
                noteStore.markPolishingFailed(
                    for: noteID,
                    variant: variant,
                    message: error.localizedDescription,
                    backendName: engine.displayName
                )
            }
        }
        return results
    }

    private func polishWithLanguageGuard(
        rawText: String,
        variant: ProcessingVariant,
        template: PromptTemplate,
        languageGuard: PolishingLanguageGuard?,
        deadline: Date? = nil
    ) async throws -> PolishingResult {
        let configuredTemplate: PromptTemplate
        if variant == .variantTwo, let humorLevel {
            configuredTemplate = template.applying(
                runtimeStyleControls: HumorRuntimeStyleControls(
                    level: humorLevel,
                    mode: humorPromptMode
                )
            )
        } else {
            configuredTemplate = template
        }

        let guardedTemplate = languageGuard?.applying(to: configuredTemplate, strict: false)
            ?? configuredTemplate
        let firstPass = try await polishWithDeadline(
            PolishingRequest(
                rawText: rawText,
                variant: variant,
                template: guardedTemplate,
                humorLevel: variant == .variantTwo ? humorLevel?.rawValue : nil
            ),
            deadline: deadline
        )

        guard let languageGuard, languageGuard.requiresStrictRetry(for: firstPass.text) else {
            return firstPass
        }

        // Q5a: never start the strict retry at or after the chain cap; keep
        // the first-pass polished text so the pipeline can translate it (Q3a).
        if let deadline, Date() >= deadline {
            return firstPass
        }

        let strictTemplate = languageGuard.applying(to: configuredTemplate, strict: true)
        do {
            let strict = try await polishWithDeadline(
                PolishingRequest(
                    rawText: rawText,
                    variant: variant,
                    template: strictTemplate,
                    humorLevel: variant == .variantTwo ? humorLevel?.rawValue : nil
                ),
                deadline: deadline
            )
            // ADR-029/Q3a: a still-wrong language after the strict retry keeps
            // the polished source-language text (translation failure, not
            // polishing failure). The pipeline verifies it, translates it via
            // the provider, or falls back to it with a signal. Inconclusive
            // (short/mixed) text is kept as-is.
            return strict
        } catch {
            // Q5a cap abort (throw or cancellation mid-retry): the first pass
            // already produced polished source-language text, so keep it as
            // completed instead of failing the variant. The pipeline then
            // translates it or falls back to it with a signal — never Raw.
            return firstPass
        }
    }

    /// Q5a: first pass and strict retry share the chain deadline. Cloud key
    /// chains must not start a new key at or after the cap.
    private func polishWithDeadline(
        _ request: PolishingRequest,
        deadline: Date?
    ) async throws -> PolishingResult {
        if let cloud = engine as? any DeadlineAwarePolishingEngine {
            return try await cloud.polish(
                request,
                keyChainSeconds: CloudKeyFailover.TimeBudget.default.keyChainSeconds,
                deadline: deadline
            )
        }
        return try await engine.polish(request)
    }
}

private extension Array where Element == ProcessingVariant {
    var polishableVariants: [ProcessingVariant] {
        filter { $0 != .raw }
    }
}

private struct PolishingLanguageGuard {
    private let sourceIsCyrillicDominant: Bool
    private let translationInstruction: String?
    private let translationFooter: String?
    private let targetLanguageName: String?
    private let verifyTargetCode: String?
    private let primaryLanguageCode: String?
    private let additionalLanguageCode: String?

    init?(
        sourceText: String,
        targetLanguage: String? = nil,
        primaryLanguageCode: String? = nil,
        additionalLanguageCode: String? = nil
    ) {
        self.primaryLanguageCode = primaryLanguageCode
        self.additionalLanguageCode = additionalLanguageCode
        let sourceIsCyrillic = Self.isCyrillicDominant(sourceText)
        let normalizedTarget = HUDPolishingTranslation.concreteLanguageCode(targetLanguage)

        // Explicit translation request (HUD "A" → target language): instruct the
        // polishing model to translate the output into the target language. This
        // supersedes any source-language lock so that, e.g., Russian speech can be
        // rendered as Spanish/English/etc. text by the polishing model. The raw
        // transcription itself is left untouched upstream; only the polished
        // variant is translated.
        if let normalizedTarget {
            let languageName = TranscriptionLanguageOption.displayName(for: normalizedTarget)
            targetLanguageName = languageName
            verifyTargetCode = normalizedTarget
            translationInstruction = """
            === TRANSLATION OVERRIDE - READ THIS FIRST, HIGHEST PRIORITY ===
            For THIS task you MUST translate the ENTIRE text into \(languageName).
            This requirement OVERRIDES and SUSPENDS every other language rule in this prompt. Ignore any instruction below that says to keep, preserve, or not change the input language, to "never translate", to "not translate the text", to output in the same language as the input, or to confirm that the output matches the input language. Those rules DO NOT apply to this task.
            Still follow the cleaning, editing, and formatting rules below, but write the final result entirely in \(languageName).
            Preserve embedded technical terms, product and company names, APIs, commands, code fragments, file paths, UI labels, and abbreviations exactly where appropriate; the surrounding prose MUST be in \(languageName).
            Return ONLY the final text. Do not mention this override or the translation.
            === END OVERRIDE ===
            """
            translationFooter = """
            === FINAL TRANSLATION REMINDER ===
            Return the text above entirely in \(languageName). Ignore any earlier instruction that says to keep the original language or not to translate. Output ONLY the final polished text in \(languageName) - no explanations, no notes, no source-language text.
            """
            sourceIsCyrillicDominant = sourceIsCyrillic
            return
        }

        // No translation requested: keep the output in the source language. When the
        // source is primarily Russian/Cyrillic, lock the output to Cyrillic so the
        // polishing model does not drift into English.
        guard sourceIsCyrillic else {
            return nil
        }

        sourceIsCyrillicDominant = true
        translationInstruction = nil
        translationFooter = nil
        targetLanguageName = nil
        verifyTargetCode = primaryLanguageCode ?? "ru"
    }

    /// Minimal script census for the *source* lock trigger only. Output gating
    /// uses `OutputLanguageVerifier`, never this count.
    private static func isCyrillicDominant(_ text: String) -> Bool {
        var cyrillic = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0041...0x005A, 0x0061...0x007A:
                latin += 1
            case 0x0400...0x04FF, 0x0500...0x052F, 0x2DE0...0x2DFF, 0xA640...0xA69F:
                cyrillic += 1
            default:
                continue
            }
        }
        return cyrillic >= 4 || (cyrillic >= 1 && cyrillic >= latin)
    }

    func applying(to template: PromptTemplate, strict: Bool) -> PromptTemplate {
        if let translationInstruction, let translationFooter, let targetLanguageName {
            let rewritten = Self.rewritingConflictingLanguageRules(
                in: template.body,
                languageName: targetLanguageName
            )
            let header: String
            if strict {
                header = """
                \(translationInstruction)

                CRITICAL: Previous output was still in the source language. You MUST translate every sentence into \(targetLanguageName) now. Do not keep source-language prose.

                """
            } else {
                header = "\(translationInstruction)\n\n"
            }
            return PromptTemplate(
                id: template.id,
                title: template.title,
                body: Self.insertingInstruction(
                    header: header,
                    footer: translationFooter,
                    into: rewritten
                )
            )
        }

        guard sourceIsCyrillicDominant else {
            return template
        }

        let instruction: String
        let footer: String
        if strict {
            instruction = """
            CRITICAL LANGUAGE LOCK:
            - The source text is written in Russian (Cyrillic).
            - Your output MUST remain in Russian (Cyrillic).
            - Do NOT translate the Russian text into English or any other language.
            - Preserve embedded English technical terms, product names, APIs, commands, code fragments, file paths, UI labels, and abbreviations exactly where appropriate.
            """
            footer = """
            === CRITICAL LANGUAGE LOCK REMINDER ===
            Output the final cleaned text in RUSSIAN (Cyrillic). Do NOT translate to English.
            """
        } else {
            instruction = """
            LANGUAGE LOCK:
            - The source text is written in Russian (Cyrillic).
            - Keep the output in Russian (Cyrillic).
            - Do NOT translate the text into English.
            - Preserve embedded English technical terms, product names, APIs, commands, code fragments, file paths, UI labels, and abbreviations exactly where appropriate.
            """
            footer = """
            === LANGUAGE LOCK REMINDER ===
            Output ONLY the final polished text in RUSSIAN (Cyrillic). Do NOT translate to English.
            """
        }

        return PromptTemplate(
            id: template.id,
            title: template.title,
            body: """
            \(instruction)

            \(template.body)

            \(footer)
            """
        )
    }

    /// ADR-029: the retry decision is an explicit wrong-language verdict from
    /// `OutputLanguageVerifier`. Inconclusive (short/mixed) text never retries.
    /// A-mode short text never retries either: identifiers, numbers, and
    /// interjections (`OK`, `42`) keep the first pass instead of being
    /// rewritten (S11 J2). Translation (E) mode and long text are unchanged.
    func requiresStrictRetry(for outputText: String) -> Bool {
        guard verifyTargetCode != nil else { return false }
        if translationInstruction == nil, OutputLanguageVerifier.isShortText(outputText) {
            return false
        }
        if case .fail = verify(outputText) { return true }
        return false
    }

    private func verify(_ outputText: String) -> OutputLanguageVerifier.Decision {
        OutputLanguageVerifier.verify(
            text: outputText,
            targetCode: verifyTargetCode ?? "en",
            primaryCode: primaryLanguageCode,
            additionalCode: additionalLanguageCode
        )
    }

    /// `PolishingPromptPolicy` fences everything after `INPUT:` as source data.
    /// Translation instructions must stay before that marker so they remain
    /// task instructions instead of being ignored as transcription content.
    private static func insertingInstruction(
        header: String,
        footer: String,
        into body: String
    ) -> String {
        if let inputRange = body.range(of: "INPUT:", options: [.backwards, .caseInsensitive]) {
            let before = body[..<inputRange.lowerBound]
            let after = body[inputRange.lowerBound...]
            return "\(header)\(before)\n\(footer)\n\n\(after)"
        }
        return "\(header)\(body)\n\n\(footer)"
    }

    private static func rewritingConflictingLanguageRules(
        in body: String,
        languageName: String
    ) -> String {
        var result = body
        let replacements: [(String, String)] = [
            (
                "Keep the language of the input. Never translate the text or replace established technical terms with awkward translated equivalents.",
                "The result MUST be written entirely in \(languageName). Translate the source if it is in another language. Preserve established technical terms rather than replacing them with awkward translated equivalents."
            ),
            (
                "Keep the main language of the input. Never translate the whole text.",
                "The result MUST be written entirely in \(languageName). Translate the whole text if the source is in another language."
            ),
            (
                "Never translate unless the input itself is already in the target language.",
                "If the input is already in \(languageName), keep it in \(languageName). Otherwise translate the entire text into \(languageName)."
            ),
            (
                "Keep the same language as input",
                "Write the result in \(languageName)"
            ),
            (
                "Keep the language of the input",
                "Write the result in \(languageName)"
            ),
            (
                "Keep the main language of the input",
                "Write the result in \(languageName)"
            ),
            (
                "Never translate the whole text",
                "Translate the whole text into \(languageName)"
            ),
            (
                "Never translate the text",
                "Translate the text into \(languageName)"
            ),
            // ADR-029: residual slot locks proven to survive the rewrite above.
            // Under an explicit translation override they are neutralized, not kept.
            (
                "Do not translate the entire message",
                "Translate the entire message into \(languageName)"
            ),
            (
                "Do not translate the whole message",
                "Translate the whole message into \(languageName)"
            ),
            (
                "stay in the input language",
                "be written entirely in \(languageName)"
            ),
            (
                "native to the input language",
                "native to \(languageName)"
            ),
            (
                "in the input language",
                "in \(languageName)"
            ),
            (
                "same language as the input",
                "the \(languageName) language"
            ),
            (
                "matches the input language",
                "is entirely in \(languageName)"
            )
        ]
        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to, options: [.caseInsensitive])
        }
        return result
    }
}

