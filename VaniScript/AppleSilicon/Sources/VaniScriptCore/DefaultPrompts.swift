import Foundation

public struct PromptPresetSettings: Codable, Equatable, Sendable {
    public var active: String // "default", "custom1", "custom2", "custom3"
    public var custom: [String: String] // ["custom1": "", "custom2": "", "custom3": ""]

    public init(active: String = "default", custom: [String: String] = ["custom1": "", "custom2": "", "custom3": ""]) {
        self.active = active
        self.custom = custom
    }
}

public struct PromptDefinition: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var stage: String
    public var description: String
    public var variables: [String]
    public var defaultText: String

    public init(id: String, label: String, stage: String, description: String, variables: [String], defaultText: String) {
        self.id = id
        self.label = label
        self.stage = stage
        self.description = description
        self.variables = variables
        self.defaultText = defaultText
    }
}

public enum DefaultPrompts {
    public static let definitions: [PromptDefinition] = [
        PromptDefinition(
            id: "transcriptionSystem",
            label: "Transcription · System",
            stage: "Transcription",
            description: "System instruction used by Gemini audio transcription.",
            variables: [],
            defaultText: """
You are a verbatim transcription engine optimized for Gaudiya Vaishnava philosophical lectures.

RULES:
1. DICTAPHONE MODE: Transcribe exact words in first person. Zero summarization.
2. Sanskrit/Bengali terms: retain in original transliteration (Krishna, Bhakti, Shastra, etc.)
3. Speaker labels: use [Speaker Name] only when multiple speakers present.
4. Unrecognized words: {unrecognized word} as last resort.
5. Timestamps for TXT: [MM:SS] at speaker changes or logical paragraphs.
6. TAIL-CHECK: Ensure transcription reaches the absolute last spoken word.

CONTEXT: Gaudiya Vaishnava tradition. Acharyas: Srila Prabhupada, Bhaktivinoda Thakur, Bhaktisiddhanta Sarasvati.
Scriptures: Bhagavad-gita, Srimad-Bhagavatam, Caitanya-caritamrita, Nectar of Devotion.
Common terms: sankirtan, kirtan, sadhana, bhakti, nama-japa, puja, guru, diksha, vaishnava, sampradaya.
"""
        ),
        PromptDefinition(
            id: "transcriptionUser",
            label: "Transcription · User",
            stage: "Transcription",
            description: "User prompt sent with audio for tagged transcript output.",
            variables: ["translationInstruction", "speakerHint", "metadataBlock", "requestedFormats", "translatedTxtExample"],
            defaultText: """
TASK:
1. Transcribe the audio in its original language.
{{translationInstruction}}
SPEAKER IDENTIFICATION HINT: Based on metadata, the primary speaker may be "{{speakerHint}}".

{{metadataBlock}}

REQUESTED FORMATS: {{requestedFormats}}

CRITICAL: YOU MUST WRAP EACH SECTION IN CLEAR TAGS.
Example:
[ORIGINAL_TXT]
(content here)
[/ORIGINAL_TXT]
{{translatedTxtExample}}
Do this for ALL formats requested: {{requestedFormats}}.
Use tags like [ORIGINAL_SRT], [ORIGINAL_VTT], [ORIGINAL_MARKDOWN], [TRANSLATED_SRT], etc.

REMAINING REQUIREMENTS:
- TXT: clean reading text with metadata at the top when provided. Preserve paragraph structure.
- SRT/VTT: split into real subtitle cues, not one large block. Keep cue lengths readable.
- Markdown: no timestamps in prose body unless absolutely necessary. Use real headings/subheadings and readable article structure for book/editorial work.
- SPEAKER TAGS: If there is only one speaker, do not repeat their name before every paragraph.
- At the absolute end, provide: "UNRECOGNIZED FRAGMENTS LIST" with a list of all {unrecognized} fragments.
"""
        ),
        PromptDefinition(
            id: "openaiWhisperPrompt",
            label: "OpenAI Whisper Hint",
            stage: "Transcription",
            description: "Optional prompt/hint passed to OpenAI audio transcription.",
            variables: [],
            defaultText: "Verbatim lecture transcription. Preserve first-person direct speech, names, Sanskrit/Bengali terms, and devotional terminology. Use standard spellings from the glossary context when possible."
        ),
        PromptDefinition(
            id: "translationSystem",
            label: "Translation · System",
            stage: "Translation",
            description: "System instruction for cloud translation providers.",
            variables: ["targetLang"],
            defaultText: """
You are a precise translation engine for Gaudiya Vaishnava lectures.

RULES:
1. Preserve meaning exactly. Do not summarize.
2. Keep names and Sanskrit/Bengali philosophical terms in standard transliteration when natural.
3. Preserve every [MM:SS] timestamp marker exactly where it appears.
4. Preserve paragraph breaks and do not collapse the text into one paragraph.
5. Translate metadata labels naturally when the target language is not English.
6. Do not add commentary, notes, or explanations.
7. Return only the translated text.
"""
        ),
        PromptDefinition(
            id: "translationUser",
            label: "Translation · User",
            stage: "Translation",
            description: "Main transcript translation prompt for cloud providers.",
            variables: ["targetLang", "speakerHintLine", "glossaryBlock", "text"],
            defaultText: """
Translate the following transcript to {{targetLang}}.
{{speakerHintLine}}
{{glossaryBlock}}
Keep all [MM:SS] timestamp markers unchanged.
Keep metadata as a separate block at the top if present.
Keep paragraph breaks. Do not return one dense paragraph.
Return only the translated text.

{{text}}
"""
        ),
        PromptDefinition(
            id: "structuredTranslationUser",
            label: "Translation · Structured Batch",
            stage: "Translation",
            description: "Strict JSON prompt for multi-segment cloud translation with split fallback.",
            variables: ["targetLang", "speakerHintLine", "glossaryBlock", "segmentsJson"],
            defaultText: """
Translate each segment to {{targetLang}}.
{{speakerHintLine}}
{{glossaryBlock}}

Return only a strict JSON array. Each array item must be {"id": "...", "text": "..."} with the same ids, count, and order as the input.
Preserve all [MM:SS] timestamp markers inside each segment exactly.
Do not merge, drop, reorder, summarize, or add commentary.

Segments:
{{segmentsJson}}
"""
        ),
        PromptDefinition(
            id: "localTranslationUser",
            label: "Local Translation",
            stage: "Translation",
            description: "Prompt used when local LLMs translate transcript batches.",
            variables: ["targetLang", "speakerHintLine", "glossaryBlock", "text"],
            defaultText: """
{{speakerHintLine}}
Translate the transcript into {{targetLang}}.
Return only the {{targetLang}} translation.
Do not explain. Do not think step by step. Do not output analysis, notes, markdown, or source-language copies.
{{glossaryBlock}}
Use the glossary spellings and translations exactly when those terms appear.
Preserve every [MM:SS] timestamp exactly.
Preserve paragraph breaks.

Transcript:
{{text}}

{{targetLang}} translation:
"""
        ),
        PromptDefinition(
            id: "documentLiteraryTranslationSystem",
            label: "Document Translation · System",
            stage: "Document Translation",
            description: "Strict system contract for literary document translation.",
            variables: ["targetLang", "responseTemplate", "chunkId", "requiredBlockIDs", "allowedStyleIDs"],
            defaultText: """
You translate structured literary documents for VaniScript.

Return exactly one JSON object matching this canonical response object shape:
{{responseTemplate}}

The exact request identity is:
- chunkId: {{chunkId}}
- required block IDs, in this exact order: {{requiredBlockIDs}}
- allowed style IDs: {{allowedStyleIDs}}

Return one output block for every required block ID, in the exact requested order.
Never merge, drop, duplicate, or invent block IDs. Never translate read-only context.
Use only captured style IDs. Preserve protected blocks and protected spans byte-for-byte,
including names, numbers, placeholders, citations, and transliteration. Do not add
headings, explanations, summaries, notes, markdown fences, or labels such as
"Translation:". Preserve the author's person, modality, repetition, and meaning.
The target language is {{targetLang}}.
"""
        ),
        PromptDefinition(
            id: "documentLiteraryTranslationUser",
            label: "Document Translation · User",
            stage: "Document Translation",
            description: "Structured request for one semantic document chunk.",
            variables: ["requestJson", "responseTemplate", "chunkId", "requiredBlockIDs", "allowedStyleIDs"],
            defaultText: """
Translate only the requested blocks in this document translation request.
The request JSON is authoritative. Do not translate read-only context.
Return the exact canonical JSON object shape shown below, with the exact chunkId,
required block IDs/order, and allowed style IDs:
{{responseTemplate}}
chunkId: {{chunkId}}
required block IDs/order: {{requiredBlockIDs}}
allowed style IDs: {{allowedStyleIDs}}

Return strict JSON and nothing else:

{{requestJson}}
"""
        ),
        PromptDefinition(
            id: "documentTranslationRepair",
            label: "Document Translation · Targeted Repair",
            stage: "Document Translation",
            description: "Repairs only invalid block IDs from one translation response.",
            variables: ["requestJson", "issues"],
            defaultText: """
Repair only the listed invalid block IDs in the supplied document translation request.
Do not regenerate or alter any other block. Preserve all protected material and style IDs.
Return the same strict vaniscript.document.translation.v1 JSON shape, with exactly the
requested block IDs in their original order and no explanation.

Validation issues:
{{issues}}

Request:
{{requestJson}}
"""
        ),
        PromptDefinition(
            id: "documentTranslationQualityReview",
            label: "Document Translation · Quality Review",
            stage: "Document Translation",
            description: "Optional issue-only quality review; never rewrites translation text.",
            variables: ["requestJson", "responseJson"],
            defaultText: """
Review this structured document translation without rewriting it.
Return JSON with an issues array only. Do not return replacement text.
Request:
{{requestJson}}

Response:
{{responseJson}}
"""
        ),
        PromptDefinition(
            id: "documentVerseClassification",
            label: "Document Translation · Verse Classification",
            stage: "Document Translation",
            description: "Optional preflight classification for ambiguous verse blocks.",
            variables: ["text"],
            defaultText: """
Classify the supplied document block for preflight only.
Return strict JSON with one policy: preserveExact, preserveTransliterationTranslateGloss,
or editorApprovedAdaptation. Do not translate or rewrite the text.
Block:
{{text}}
"""
        ),
        PromptDefinition(
            id: "literaryPolishSystem",
            label: "Polish · System",
            stage: "Editing",
            description: "System instruction for translation polishing.",
            variables: ["targetLang"],
            defaultText: "You revise translations into natural target-language prose while preserving exact meaning and timestamps."
        ),
        PromptDefinition(
            id: "literaryPolishUser",
            label: "Polish · User",
            stage: "Editing",
            description: "Prompt used by Polish Translation in review/editing.",
            variables: ["targetLang", "speakerHintLine", "glossaryBlock", "russianPolishRule", "text"],
            defaultText: """
Polish the following translated fragment so it sounds natural, fluent, and literary in {{targetLang}}.
{{speakerHintLine}}
{{glossaryBlock}}

Rules:
1. Preserve the meaning exactly. Do not add new meaning, do not summarize, and do not remove details.
2. Make the wording natural for a native reader of the target language, with correct grammar, cases, agreement, and word order.
3. Avoid stiff word-for-word translation. Rewrite only as much as needed so the sentence sounds idiomatic.
4. Preserve every existing [MM:SS] timestamp exactly if present. Do not add a new timestamp.
5. Preserve glossary terms exactly.
6. Return only the revised replacement text. No notes, labels, markdown, quote marks, or headings such as "Revised Russian:".
{{russianPolishRule}}

Fragment:
{{text}}
"""
        ),
        PromptDefinition(
            id: "audioReview",
            label: "Audio-Aware Review",
            stage: "Editing",
            description: "Prompt used when reviewing a selected fragment against audio.",
            variables: ["modeLabel", "speakerHintLine", "glossaryBlock", "returnLanguageRule", "selectedText"],
            defaultText: """
You are doing an audio-aware review of a short highlighted transcript fragment.
Mode: {{modeLabel}}.
{{speakerHintLine}}
{{glossaryBlock}}

Task:
1. Listen to the audio and locate the highlighted fragment.
2. Correct only this highlighted fragment.
3. Preserve the spoken meaning exactly. Do not polish, summarize, or expand.
4. Use glossary spellings and translations exactly when applicable.
{{returnLanguageRule}}

Highlighted fragment:
{{selectedText}}

Output only the corrected replacement text.
Do not return analysis, notes, markdown, labels, or quote marks.
"""
        ),
        PromptDefinition(
            id: "shortsPlannerSystem",
            label: "Shorts/Reels · System",
            stage: "Shorts & Reels",
            description: "System instruction used by OpenAI for Shorts/Reels planning.",
            variables: [],
            defaultText: "You select short video clips from prepared transcripts. Return only the requested JSON."
        ),
        PromptDefinition(
            id: "shortsPlanner",
            label: "Shorts/Reels · User",
            stage: "Shorts & Reels",
            description: "Prompt that finds interesting short-form clips and captions.",
            variables: ["speakerMetadataLine", "count", "minDurationSec", "maxDurationSec", "modeInstruction", "captionSchema", "transcript"],
            defaultText: """
You are selecting clips for YouTube Shorts, Instagram Reels, and TikTok.
Context: Vaishnava lecture. Prefer moments with a clear story, paradox, emotional point, practical teaching, or memorable quote.
{{speakerMetadataLine}}
Find exactly {{count}} candidate clips.
Each clip must be between {{minDurationSec}} and {{maxDurationSec}} seconds.
{{modeInstruction}}
{{captionSchema}}
captionText is the exact short-form subtitle script for this clip. It is not a summary.
captionText must contain many dense timestamped subtitle cues, one cue per line, formatted exactly as "[MM:SS] text".
Use absolute timestamps from the transcript, not relative timestamps. The first caption timestamp should be the clip start or the first spoken line inside the clip.
Create a new caption cue roughly every 1.5-4 seconds, or whenever the spoken phrase naturally changes.
Never put a whole 45-180 second clip into one or two caption cues. That makes the reel unusable.
Each caption cue should fit on a phone screen: aim for one line, maximum two short lines, usually 3-10 words or about 18-42 characters.
Preserve meaning and spoken order. Do not add commentary, explanations, markdown, numbering, or speaker labels inside captionText.
For bilingual output, sourceCaptionText and targetCaptionText must use the same timestamp markers and the same number/order of cues so both videos stay aligned.
Example captionText format: "[04:56] The spiritual city is\\n[04:59] the spiritual character of His residence\\n[05:03] In building the city of Mayapur"
Use short category tags such as story, philosophy, quote, teaching, humor, or history.
Do not invent timestamps. Use only timestamps from the transcript.

Transcript:
{{transcript}}
"""
        ),
        PromptDefinition(
            id: "documentMarkdown",
            label: "Export · Markdown",
            stage: "Export",
            description: "Prompt that formats final Markdown documents.",
            variables: ["targetLang", "text"],
            defaultText: """
You are a formatting editor. Create a polished {{targetLang}} Markdown document from the prepared transcript below.

Hard rules:
1. Do not rewrite, paraphrase, summarize, correct, remove, or add transcript content.
2. Preserve the transcript text exactly, except removing timestamp markers if present.
3. You may add Markdown structure only: title, metadata block, table of contents, section headings, bold emphasis for short labels, horizontal rules, and paragraph breaks.
4. Divide the document by meaning. Section headings must describe the actual topic of the section, not merely copy the first sentence.
5. Preserve all metadata at the top and localize metadata labels to the document language.
6. Return only the Markdown document. No notes or explanations.

For Russian Markdown use Russian labels such as "Дата", "Место", "Лектор", "Интервьюер / Участники", and "Содержание".

<<<TRANSCRIPT>>>
{{text}}
<<<DOCUMENT>>>
"""
        ),
        PromptDefinition(
            id: "documentSubtitles",
            label: "Export · SRT/VTT",
            stage: "Export",
            description: "Prompt that formats final subtitle files.",
            variables: ["format", "subtitleMaxCharsPerLine", "subtitleMaxLines", "text"],
            defaultText: """
You are a professional subtitle formatter. Format the prepared transcript as valid {{format}}.

Hard rules:
1. Do not rewrite, paraphrase, translate, correct, remove, or add spoken text.
2. Keep timings accurate and monotonic. Preserve the provided timing boundaries as closely as possible.
3. Prefer no more than {{subtitleMaxCharsPerLine}} characters per line and no more than {{subtitleMaxLines}} lines per subtitle cue.
4. Break subtitles at natural phrase boundaries.
5. Do not split proper names, titles, Sanskrit terms, or devotional names across subtitle cues or lines when avoidable.
6. If a phrase would read badly when split, make the cue slightly shorter or longer rather than splitting the phrase awkwardly.
7. Return only valid {{format}}. No notes, no markdown fences, no explanations.

<<<TRANSCRIPT>>>
{{text}}
<<<{{format}}>>>
"""
        ),
        PromptDefinition(
            id: "localMarkdownPart",
            label: "Local Markdown Part",
            stage: "Export",
            description: "Prompt for chunked local Markdown formatting.",
            variables: ["partNumber", "totalParts", "targetLang", "text"],
            defaultText: """
You are formatting part {{partNumber}} of {{totalParts}} of a {{targetLang}} Markdown document.

Hard rules:
1. Return only Markdown body sections for this fragment.
2. Do not include document title, metadata, table of contents, "Содержание", "Contents", or horizontal rules.
3. Do not rewrite, paraphrase, summarize, correct, remove, or add transcript content.
4. Remove timestamp markers if present.
5. Add only meaningful section headings and paragraph breaks.
6. If the fragment continues a previous topic, use a continuation heading only when it is genuinely needed.
7. No notes, no explanations, no markdown fences.

<<<TRANSCRIPT_FRAGMENT>>>
{{text}}
<<<DOCUMENT_PART>>>
"""
        )
    ]

    public static let defaultPresets: [String: PromptPresetSettings] = Dictionary(
        uniqueKeysWithValues: definitions.map {
            ($0.id, PromptPresetSettings(active: "default", custom: ["custom1": "", "custom2": "", "custom3": ""]))
        }
    )

    public static func definition(id: String) -> PromptDefinition? {
        definitions.first { $0.id == id }
    }

    public static func activeText(id: String, promptPresets: [String: PromptPresetSettings]) -> String {
        guard let definition = definition(id: id) else { return "" }
        let preset = promptPresets[id] ?? defaultPresets[id] ?? PromptPresetSettings()
        guard preset.active != "default" else { return definition.defaultText }

        let custom = preset.custom[preset.active]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? definition.defaultText : custom
    }

    public static func render(
        id: String,
        promptPresets: [String: PromptPresetSettings],
        variables: [String: String]
    ) -> String {
        var text = activeText(id: id, promptPresets: promptPresets)
        for (key, value) in variables {
            text = text.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return text
    }
}
