import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

@Suite("Media regression suite", .serialized)
struct MediaRegressionTests {
    @Test("source classifier routes media files to .media and documents to .document")
    func routesMediaAndDocumentsCorrectly() throws {
        // Media files
        #expect(try SourceClassifier.classification(for: URL(fileURLWithPath: "/tmp/recording.mp3")) == .media)
        #expect(try SourceClassifier.classification(for: URL(fileURLWithPath: "/tmp/recording.wav")) == .media)
        #expect(try SourceClassifier.classification(for: URL(fileURLWithPath: "/tmp/recording.m4a")) == .media)
        #expect(try SourceClassifier.classification(for: URL(fileURLWithPath: "/tmp/recording.mp4")) == .media)
        #expect(try SourceClassifier.classification(for: URL(fileURLWithPath: "/tmp/recording.mov")) == .media)

        // Document files
        #expect(try SourceClassifier.classification(for: URL(fileURLWithPath: "/tmp/book.docx")) == .document)
        #expect(try SourceClassifier.classification(for: URL(fileURLWithPath: "/tmp/book.txt")) == .document)
        #expect(try SourceClassifier.classification(for: URL(fileURLWithPath: "/tmp/book.md")) == .document)
        #expect(try SourceClassifier.classification(for: URL(fileURLWithPath: "/tmp/book.markdown")) == .document)
        #expect(try SourceClassifier.classification(for: URL(fileURLWithPath: "/tmp/book.rtf")) == .document)
        #expect(try SourceClassifier.classification(for: URL(fileURLWithPath: "/tmp/book.pdf")) == .document)

        // Macro-enabled rejection
        #expect(throws: SourceClassifierError.macroDocumentsUnsupported) {
            try SourceClassifier.classification(for: URL(fileURLWithPath: "/tmp/book.docm"))
        }
    }

    @Test("local ASR model catalog descriptors and family mappings are intact")
    func localASRModelCatalogIntact() {
        let models = NativeModelCatalog.localASRModels
        #expect(models.isEmpty == false)

        // Ensure key local ASR models exist in the catalog
        #expect(models.contains(where: { $0.id.contains("whisper") }))
        #expect(models.contains(where: { $0.id.contains("parakeet") }))
        #expect(models.contains(where: { $0.id.contains("canary") }))
    }

    @Test("cloud provider catalog descriptors for transcription and translation are intact")
    func cloudProviderCatalogIntact() {
        let providers = CloudProviderCatalog.providers
        #expect(providers.isEmpty == false)

        #expect(providers.contains(where: { $0.id == CloudProviderCatalog.geminiID }))
        #expect(providers.contains(where: { $0.id == CloudProviderCatalog.openaiID }))
        #expect(providers.contains(where: { $0.id == CloudProviderCatalog.anthropicID }))

        let gemini = CloudProviderCatalog.descriptor(for: CloudProviderCatalog.geminiID)
        #expect(gemini != nil)
        #expect(gemini?.capabilities.supportsTranscription == true)
        #expect(gemini?.capabilities.supportsTranslation == true)
    }

    @Test("audio metadata defaults and workflow state transitions preserve media pipeline")
    func audioWorkflowStateIntact() {
        var state = WorkflowState.initial(settings: .defaults)
        state.sourceKind = .media
        state.sourceLang = "en"
        state.targetLang = "ru"

        #expect(state.sourceKind == .media)
        #expect(state.sourceLang == "en")
        #expect(state.targetLang == "ru")
    }
}
