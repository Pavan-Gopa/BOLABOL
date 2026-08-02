import Foundation

/// A deliberately short instruction for the first, audio-to-text stage of cloud dictation.
///
/// Variant 1/2 editing is intentionally excluded from this prompt. Those transformations
/// run as a separate text-only request after this stage has produced a faithful Raw transcript.
public enum CloudRawTranscriptionPrompt {
    public static func instruction(
        forceTargetLanguage: Bool,
        targetLanguageName: String
    ) -> String {
        let languageRule: String
        if forceTargetLanguage {
            let target = targetLanguageName
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let language = target.isEmpty ? "English" : target
            languageRule = """
            - Write the entire result in \(language). If the speech uses another language, \
            translate it faithfully into \(language) without changing its meaning or level of detail.
            """
        } else {
            languageRule = """
            - Keep the language spoken in the audio. Do not translate.
            """
        }

        return """
        Transcribe the attached speech accurately and return only the transcript.

        Apply light cleanup only:
        - Remove meaningless hesitation sounds and filler words.
        - When a word or phrase is accidentally repeated while the speaker restarts, keep it only once.
        - Keep the final intended wording and remove abandoned false starts.
        - Add obvious punctuation and capitalization.
        - Split long speech into natural paragraphs when helpful.
        \(languageRule)
        Preserve every meaningful idea, detail, name, technical term, and the speaker's original order.
        Do not summarize, reinterpret, improve the argument, or rewrite the style.
        Before returning, scan once for accidental adjacent duplicates and remove them.
        Do not add an introduction, explanation, label, or Markdown.
        """
    }
}
