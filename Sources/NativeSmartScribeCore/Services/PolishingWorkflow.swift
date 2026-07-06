import Foundation

@MainActor
public final class PolishingWorkflow {
    private let noteStore: NoteStore
    private let engine: any PolishingEngine
    private let templateProvider: (ProcessingVariant) -> PromptTemplate
    private let messageProvider: (AppTextKey) -> String

    public init(
        noteStore: NoteStore,
        engine: any PolishingEngine,
        templateProvider: @escaping (ProcessingVariant) -> PromptTemplate = {
            .defaultTemplate(for: $0)
        },
        messageProvider: @escaping (AppTextKey) -> String = {
            AppText.localized($0, language: .english)
        }
    ) {
        self.noteStore = noteStore
        self.engine = engine
        self.templateProvider = templateProvider
        self.messageProvider = messageProvider
    }

    @discardableResult
    public func polishNote(
        _ noteID: SmartScribeNote.ID,
        variants: [ProcessingVariant] = [.variantOne, .variantTwo]
    ) async -> [ProcessingVariant: PolishingResult] {
        var results: [ProcessingVariant: PolishingResult] = [:]
        guard let note = noteStore.note(withID: noteID) else { return results }
        let rawText = note.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let languageGuard = PolishingLanguageGuard(sourceText: rawText)

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
                    languageGuard: languageGuard
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
        languageGuard: PolishingLanguageGuard?
    ) async throws -> PolishingResult {
        let guardedTemplate = languageGuard?.applying(to: template, strict: false) ?? template
        var result = try await engine.polish(
            PolishingRequest(
                rawText: rawText,
                variant: variant,
                template: guardedTemplate
            )
        )

        guard let languageGuard, languageGuard.requiresStrictRetry(for: result.text) else {
            return result
        }

        let strictTemplate = languageGuard.applying(to: template, strict: true)
        result = try await engine.polish(
            PolishingRequest(
                rawText: rawText,
                variant: variant,
                template: strictTemplate
            )
        )
        return result
    }
}

private extension Array where Element == ProcessingVariant {
    var polishableVariants: [ProcessingVariant] {
        filter { $0 != .raw }
    }
}

private struct PolishingLanguageGuard {
    private let sourceIsCyrillicDominant: Bool

    init?(sourceText: String) {
        let sourceProfile = ScriptProfile(text: sourceText)
        guard sourceProfile.isCyrillicDominant else {
            return nil
        }

        self.sourceIsCyrillicDominant = true
    }

    func applying(to template: PromptTemplate, strict: Bool) -> PromptTemplate {
        guard sourceIsCyrillicDominant else {
            return template
        }

        let instruction: String
        if strict {
            instruction = """
            CRITICAL LANGUAGE LOCK:
            - The source text is primarily Russian written in Cyrillic.
            - Your output MUST remain primarily Russian written in Cyrillic.
            - If you answer mostly in English or another non-Cyrillic language, the answer is wrong.
            - Preserve embedded English technical terms, product names, APIs, commands, code fragments, file paths, UI labels, and abbreviations exactly where appropriate.
            """
        } else {
            instruction = """
            LANGUAGE LOCK:
            - The source text is primarily Russian written in Cyrillic.
            - Keep the output primarily in Russian written in Cyrillic.
            - Preserve embedded English technical terms, product names, APIs, commands, code fragments, file paths, UI labels, and abbreviations exactly where appropriate.
            """
        }

        return PromptTemplate(
            id: template.id,
            title: template.title,
            body: """
            \(instruction)

            \(template.body)
            """
        )
    }

    func requiresStrictRetry(for outputText: String) -> Bool {
        let outputProfile = ScriptProfile(text: outputText)
        return sourceIsCyrillicDominant && outputProfile.isClearlyNonCyrillicComparedToCyrillicSource
    }
}

private struct ScriptProfile {
    let cyrillicCount: Int
    let latinCount: Int

    init(text: String) {
        var cyrillicCount = 0
        var latinCount = 0

        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0041...0x005A, 0x0061...0x007A:
                latinCount += 1
            case 0x0400...0x04FF, 0x0500...0x052F, 0x2DE0...0x2DFF, 0xA640...0xA69F:
                cyrillicCount += 1
            default:
                continue
            }
        }

        self.cyrillicCount = cyrillicCount
        self.latinCount = latinCount
    }

    var isCyrillicDominant: Bool {
        cyrillicCount >= 8 && cyrillicCount > latinCount
    }

    var isClearlyNonCyrillicComparedToCyrillicSource: Bool {
        latinCount >= 12 && cyrillicCount * 2 < latinCount
    }
}
