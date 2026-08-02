import NativeBlaboomCore
import Testing

struct SpeechCleanupNormalizerTests {
    @Test
    func variantOneRemovesCommonRussianFillersAndAdjacentDuplicates() {
        let input = "ну вот я вот хочу ну записать записать текст и типа потом его поправить"

        let output = SpeechCleanupNormalizer.normalize(input, mode: .lightCleanup)

        #expect(output == "Я хочу записать текст и потом его поправить.")
    }

    @Test
    func variantOneSplitsLongDictationIntoShortParagraphs() {
        let input = "сегодня я проверил транскрибацию и в целом все работает нормально просто нужно убрать повторы и мусорные слова. потом я открыл настройки и проверил модели и вроде бы все тоже работает. но текст после диктовки все равно надо делать чище"

        let output = SpeechCleanupNormalizer.normalize(input, mode: .lightCleanup)

        #expect(output.contains("\n\n"))
        #expect(output.hasPrefix("Сегодня"))
        #expect(output.hasSuffix("."))
    }

    @Test
    func cloudRawCleanupRemovesDuplicatesFlashLiteMayLeaveBehind() {
        let input = "Ну вот, я я хочу сказать, что сначала нужно, нужно получить транскрипцию. То есть, как бы, смысл должен остаться прежним."

        let output = SpeechCleanupNormalizer.normalize(input, mode: .lightCleanup)

        #expect(!output.localizedCaseInsensitiveContains("я я"))
        #expect(!output.localizedCaseInsensitiveContains("нужно, нужно"))
        #expect(!output.localizedCaseInsensitiveContains("как бы"))
        #expect(output.localizedCaseInsensitiveContains("смысл должен остаться прежним"))
    }
}
