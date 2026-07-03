import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Hugging Face model manifest")
struct HuggingFaceModelManifestTests {
    @Test("decodes current rfilename siblings")
    func decodesCurrentRFilenameSiblings() throws {
        let data = #"{"siblings":[{"rfilename":"config.json"},{"rfilename":"model.safetensors"}]}"#.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(HuggingFaceModelManifest.self, from: data)

        #expect(manifest.files == ["config.json", "model.safetensors"])
    }

    @Test("decodes legacy rpath siblings")
    func decodesLegacyRPathSiblings() throws {
        let data = #"{"siblings":[{"rpath":"tokenizer.json"}]}"#.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(HuggingFaceModelManifest.self, from: data)

        #expect(manifest.files == ["tokenizer.json"])
    }
}
