import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

@Suite("Source classifier")
struct SourceClassifierTests {
    @Test("routes media and supported documents without probing duration")
    func classifiesSupportedExtensions() throws {
        #expect(SourceClassifier.classify(URL(fileURLWithPath: "/tmp/lecture.mp3")) == .media)
        #expect(SourceClassifier.classify(URL(fileURLWithPath: "/tmp/lecture.mov")) == .media)
        #expect(SourceClassifier.classify(URL(fileURLWithPath: "/tmp/book.docx")) == .document)
        #expect(SourceClassifier.classify(URL(fileURLWithPath: "/tmp/book.txt")) == .document)
        #expect(SourceClassifier.classify(URL(fileURLWithPath: "/tmp/book.md")) == .document)
        #expect(SourceClassifier.classify(URL(fileURLWithPath: "/tmp/book.rtf")) == .document)
        #expect(SourceClassifier.classify(URL(fileURLWithPath: "/tmp/book.pdf")) == .document)
    }

    @Test("rejects macro documents and unknown extensions honestly")
    func rejectsUnsafeOrUnknownExtensions() {
        #expect(throws: SourceClassifierError.macroDocumentsUnsupported) {
            try SourceClassifier.classification(for: URL(fileURLWithPath: "/tmp/book.docm"))
        }
        #expect(throws: SourceClassifierError.unsupportedFileType("zip")) {
            try SourceClassifier.classification(for: URL(fileURLWithPath: "/tmp/archive.zip"))
        }
    }
}
