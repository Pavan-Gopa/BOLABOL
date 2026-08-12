import CoreML
import Foundation
@testable import NativeBolabol
import NativeBolabolCore
import Testing

// MARK: - Direct Engine Construction Tests (BLOCK-S9-004)

struct DirectEngineConstructionTests {

    @Test
    func constructsCanaryFlashCoreMLEngine() {
        let catalog = TranscriptionModelCatalog.nativeWhisperKit
        let model = catalog.model(withID: "canary-180m-flash-coreml")!
        let folderURL = URL(fileURLWithPath: "/tmp/bolabol-test-canary-flash")

        let engine = CanaryCoreMLEngine(model: model, modelFolderURL: folderURL)
        #expect(engine.id == "canary-canary-180m-flash-coreml")
        #expect(engine.displayName.contains("Canary Core ML"))
    }

    @Test
    func constructsCanary1BCoreMLEngine() {
        let catalog = TranscriptionModelCatalog.nativeWhisperKit
        let model = catalog.model(withID: "canary-1b-v2-coreml")!
        let folderURL = URL(fileURLWithPath: "/tmp/bolabol-test-canary-1b")

        let engine = CanaryCoreMLEngine(model: model, modelFolderURL: folderURL)
        #expect(engine.id == "canary-canary-1b-v2-coreml")
        #expect(engine.displayName.contains("Canary Core ML"))
    }

    @Test
    func constructsGigaAMCoreMLEngine() {
        let catalog = TranscriptionModelCatalog.nativeWhisperKit
        let model = catalog.model(withID: "gigaam-v3-rnnt-coreml")!
        let folderURL = URL(fileURLWithPath: "/tmp/bolabol-test-gigaam")

        let engine = GigaAMCoreMLEngine(model: model, modelFolderURL: folderURL)
        #expect(engine.id == "gigaam-gigaam-v3-rnnt-coreml")
        #expect(engine.displayName.contains("GigaAM Core ML"))
    }

    @Test
    func missingModelDirectoryThrowsHonestErrorOnTranscribe() async throws {
        let catalog = TranscriptionModelCatalog.nativeWhisperKit
        let model = catalog.model(withID: "canary-180m-flash-coreml")!
        let nonExistentURL = URL(fileURLWithPath: "/tmp/bolabol-nonexistent-\(UUID().uuidString)")

        let engine = CanaryCoreMLEngine(model: model, modelFolderURL: nonExistentURL)
        let audioURL = URL(fileURLWithPath: "/tmp/dummy.wav")
        let request = TranscriptionRequest(audioFileURL: audioURL, forcedLanguageCode: "en")

        // Transcribe on non-existent folder throws missingModelDirectory or modelNotLoaded error
        await #expect(throws: (any Error).self) {
            try await engine.transcribe(request)
        }
    }
}

// MARK: - TranscriptionEngineStore Wiring Tests (BLOCK-S9-004)

@MainActor
struct EngineStoreWiringTests {

    @Test
    func storeReturnsCanaryEngineWhenCanaryModelActive() throws {
        let catalog = TranscriptionModelCatalog.nativeWhisperKit
        guard let model = catalog.model(withID: "canary-180m-flash-coreml") else {
            Issue.record("canary-180m-flash-coreml not in catalog")
            return
        }

        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("bolabol-test-canary-\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let modelDir = tempDir.appendingPathComponent(model.relativeStorageSubpath, isDirectory: true)
        try fileManager.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // Create required complete GO model files for Canary Flash
        for item in ["CanaryEncoder.mlmodelc", "CanaryPrefill.mlmodelc", "CanaryDecoder.mlmodelc"] {
            try fileManager.createDirectory(at: modelDir.appendingPathComponent(item), withIntermediateDirectories: true)
        }
        try "{}".write(to: modelDir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: modelDir.appendingPathComponent("vocab.json"), atomically: true, encoding: .utf8)

        let tempDefaults = UserDefaults(suiteName: "bolabol-test-\(UUID().uuidString)")!
        defer { tempDefaults.removePersistentDomain(forName: tempDefaults.description) }

        let modelStore = TranscriptionModelStore(
            catalog: catalog,
            userDefaults: tempDefaults,
            fileManager: fileManager,
            modelsDirectory: tempDir
        )

        modelStore.activate(model)
        #expect(modelStore.activeModel?.id == model.id)
        #expect(modelStore.activeDownloadedModel() != nil)

        let engineStore = TranscriptionEngineStore.live()
        let activeEngine = engineStore.activeEngine(modelStore: modelStore)

        #expect(activeEngine is CanaryCoreMLEngine)
        #expect(activeEngine.id == "canary-canary-180m-flash-coreml")
    }

    @Test
    func storeReturnsGigaAMEngineWhenGigaAMModelActive() throws {
        let catalog = TranscriptionModelCatalog.nativeWhisperKit
        guard let model = catalog.model(withID: "gigaam-v3-rnnt-coreml") else {
            Issue.record("gigaam-v3-rnnt-coreml not in catalog")
            return
        }

        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("bolabol-test-gigaam-\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let modelDir = tempDir.appendingPathComponent(model.relativeStorageSubpath, isDirectory: true)
        try fileManager.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // Create required complete GO model files for GigaAM
        for item in ["Encoder.mlmodelc", "Predictor.mlmodelc", "JointDecision.mlmodelc"] {
            try fileManager.createDirectory(at: modelDir.appendingPathComponent(item), withIntermediateDirectories: true)
        }
        try "vocab".write(to: modelDir.appendingPathComponent("vocab.txt"), atomically: true, encoding: .utf8)

        let tempDefaults = UserDefaults(suiteName: "bolabol-test-\(UUID().uuidString)")!
        defer { tempDefaults.removePersistentDomain(forName: tempDefaults.description) }

        let modelStore = TranscriptionModelStore(
            catalog: catalog,
            userDefaults: tempDefaults,
            fileManager: fileManager,
            modelsDirectory: tempDir
        )

        modelStore.activate(model)
        #expect(modelStore.activeModel?.id == model.id)
        #expect(modelStore.activeDownloadedModel() != nil)

        let engineStore = TranscriptionEngineStore.live()
        let activeEngine = engineStore.activeEngine(modelStore: modelStore)

        #expect(activeEngine is GigaAMCoreMLEngine)
        #expect(activeEngine.id == "gigaam-gigaam-v3-rnnt-coreml")
    }

    @Test
    func storeReturnsUnavailableEngineWhenModelFilesMissing() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("bolabol-test-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tempDefaults = UserDefaults(suiteName: "bolabol-test-\(UUID().uuidString)")!
        defer { tempDefaults.removePersistentDomain(forName: tempDefaults.description) }

        let modelStore = TranscriptionModelStore(
            catalog: TranscriptionModelCatalog.nativeWhisperKit,
            userDefaults: tempDefaults,
            fileManager: .default,
            modelsDirectory: tempDir
        )

        let engineStore = TranscriptionEngineStore.live()
        let activeEngine = engineStore.activeEngine(modelStore: modelStore)

        #expect(activeEngine is UnavailableTranscriptionEngine)
    }
}

// MARK: - Float16 Dtype-Aware Regression Tests (BLOCK-S9-001)

struct Float16RegressionTests {

    @Test
    func gigaAMFloat16MultiArrayDtypeAwareReading() throws {
        // Create an MLMultiArray with Float16 data type (matching GigaAM encoder output)
        let shape: [Int] = [1, 4, 1]
        let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float16)

        // Known Float16 values to write directly to memory
        let expectedValues: [Float16] = [1.5, -2.25, 0.0, 3.125]
        let pointer = array.dataPointer.bindMemory(to: Float16.self, capacity: expectedValues.count)
        for i in 0..<expectedValues.count {
            pointer[i] = expectedValues[i]
        }

        // Run through product dtype-aware floatValue(from:at:) helper (GigaAMCoreMLEngine.swift:563)
        let val0 = floatValue(from: array, at: 0)
        let val1 = floatValue(from: array, at: 1)
        let val2 = floatValue(from: array, at: 2)
        let val3 = floatValue(from: array, at: 3)

        // Assert exact values read as Float
        #expect(val0 == 1.5)
        #expect(val1 == -2.25)
        #expect(val2 == 0.0)
        #expect(val3 == 3.125)

        // Verify elementOffset indexing helper works with multi-dimensional strides
        let offset0 = elementOffset(array, indices: [0, 0, 0])
        let offset1 = elementOffset(array, indices: [0, 1, 0])
        let offset2 = elementOffset(array, indices: [0, 2, 0])
        let offset3 = elementOffset(array, indices: [0, 3, 0])

        #expect(floatValue(from: array, at: offset0) == 1.5)
        #expect(floatValue(from: array, at: offset1) == -2.25)
        #expect(floatValue(from: array, at: offset2) == 0.0)
        #expect(floatValue(from: array, at: offset3) == 3.125)
    }

    @Test
    func floatValueHelperHandlesFloat32AndDouble() throws {
        let f32Array = try MLMultiArray(shape: [2], dataType: .float32)
        let f32Ptr = f32Array.dataPointer.bindMemory(to: Float.self, capacity: 2)
        f32Ptr[0] = 42.5
        f32Ptr[1] = -10.0
        #expect(floatValue(from: f32Array, at: 0) == 42.5)
        #expect(floatValue(from: f32Array, at: 1) == -10.0)

        let dblArray = try MLMultiArray(shape: [2], dataType: .double)
        let dblPtr = dblArray.dataPointer.bindMemory(to: Double.self, capacity: 2)
        dblPtr[0] = 3.14159
        dblPtr[1] = 2.71828
        #expect(abs(floatValue(from: dblArray, at: 0) - 3.14159) < 1e-4)
        #expect(abs(floatValue(from: dblArray, at: 1) - 2.71828) < 1e-4)
    }
}

// MARK: - Product Code Engine Chunking Tests (BLOCK-S9-004)

struct ProductEngineChunkingTests {

    @Test
    func canaryFlashChunkingProductCode() {
        let maxChunkSamples = 160_000 // 10 seconds at 16 kHz

        // Single chunk within max limit
        let singleSamples = [Float](repeating: 0.1, count: 160_000)
        let singleChunks = CanaryCoreMLEngine.chunk(samples: singleSamples, maxSamples: maxChunkSamples)
        #expect(singleChunks.count == 1)
        #expect(singleChunks[0].count == 160_000)

        // Multiple chunks exceeding limit
        let doubleSamples = [Float](repeating: 0.2, count: 320_000)
        let doubleChunks = CanaryCoreMLEngine.chunk(samples: doubleSamples, maxSamples: maxChunkSamples)
        #expect(doubleChunks.count == 2)
        #expect(doubleChunks[0].count == 160_000)
        #expect(doubleChunks[1].count == 160_000)

        // Partial final chunk
        let partialSamples = [Float](repeating: 0.3, count: 240_000)
        let partialChunks = CanaryCoreMLEngine.chunk(samples: partialSamples, maxSamples: maxChunkSamples)
        #expect(partialChunks.count == 2)
        #expect(partialChunks[0].count == 160_000)
        #expect(partialChunks[1].count == 80_000)
    }

    @Test
    func canary1BChunkingProductCode() {
        let maxChunkSamples = 240_000 // 15 seconds at 16 kHz

        let exactSamples = [Float](repeating: 0.5, count: 240_000)
        let exactChunks = CanaryCoreMLEngine.chunk(samples: exactSamples, maxSamples: maxChunkSamples)
        #expect(exactChunks.count == 1)
        #expect(exactChunks[0].count == 240_000)

        let samples = [Float](repeating: 0.5, count: 360_000) // 22.5 seconds
        let chunks = CanaryCoreMLEngine.chunk(samples: samples, maxSamples: maxChunkSamples)
        #expect(chunks.count == 2)
        #expect(chunks[0].count == 240_000)
        #expect(chunks[1].count == 120_000)
    }

    @Test
    func gigaAMChunkingProductCode() {
        let maxChunkSamples = 480_000 // 30 seconds at 16 kHz

        // Exact 30 seconds
        let exactSamples = [Float](repeating: 0.4, count: 480_000)
        let exactChunks = GigaAMCoreMLEngine.chunk(samples: exactSamples, maxSamples: maxChunkSamples)
        #expect(exactChunks.count == 1)
        #expect(exactChunks[0].count == 480_000)

        // Audio exceeding 30 seconds (~40 seconds)
        let longSamples = [Float](repeating: 0.4, count: 640_000)
        let longChunks = GigaAMCoreMLEngine.chunk(samples: longSamples, maxSamples: maxChunkSamples)
        #expect(longChunks.count == 2)
        #expect(longChunks[0].count == 480_000)
        #expect(longChunks[1].count == 160_000)
    }
}

// MARK: - Language Validation Tests (BLOCK-S9-002, BLOCK-S9-003)

struct LanguageValidationTests {

    @Test
    func canaryFlashLanguageValidationViaProductCode() async throws {
        let model = TranscriptionModelCatalog.nativeWhisperKit.model(withID: "canary-180m-flash-coreml")!
        let engine = CanaryCoreMLEngine(model: model, modelFolderURL: URL(fileURLWithPath: "/tmp"))

        // nil forcedLanguageCode -> throws unsupportedLanguage
        let reqNil = TranscriptionRequest(audioFileURL: nil, forcedLanguageCode: nil)
        await #expect(throws: CanaryTranscriptionError.self) {
            try await engine.resolveLanguage(reqNil)
        }

        // Unsupported language -> throws unsupportedLanguage
        let reqUnsupported = TranscriptionRequest(audioFileURL: nil, forcedLanguageCode: "zh")
        await #expect(throws: CanaryTranscriptionError.self) {
            try await engine.resolveLanguage(reqUnsupported)
        }

        // Supported language -> succeeds
        for lang in ["en", "de", "fr", "es"] {
            let reqSupported = TranscriptionRequest(audioFileURL: nil, forcedLanguageCode: lang)
            let resolved = try await engine.resolveLanguage(reqSupported)
            #expect(resolved == lang)
        }
    }

    @Test
    func gigaAMLanguageValidationViaProductCode() async throws {
        let model = TranscriptionModelCatalog.nativeWhisperKit.model(withID: "gigaam-v3-rnnt-coreml")!
        let engine = GigaAMCoreMLEngine(model: model, modelFolderURL: URL(fileURLWithPath: "/tmp"))

        // nil forcedLanguageCode -> throws unsupportedLanguage
        let reqNil = TranscriptionRequest(audioFileURL: nil, forcedLanguageCode: nil)
        await #expect(throws: GigaAMTranscriptionError.self) {
            try await engine.resolveLanguage(reqNil)
        }

        // Non-Russian language -> throws unsupportedLanguage
        let reqEn = TranscriptionRequest(audioFileURL: nil, forcedLanguageCode: "en")
        await #expect(throws: GigaAMTranscriptionError.self) {
            try await engine.resolveLanguage(reqEn)
        }

        // Translation requested -> throws translationUnsupported
        let reqTrans = TranscriptionRequest(audioFileURL: nil, forcedLanguageCode: "ru", translateToEnglish: true)
        await #expect(throws: GigaAMTranscriptionError.self) {
            try await engine.resolveLanguage(reqTrans)
        }

        // Russian language -> succeeds
        let reqRu = TranscriptionRequest(audioFileURL: nil, forcedLanguageCode: "ru")
        let resolved = try await engine.resolveLanguage(reqRu)
        #expect(resolved == "ru")
    }
}
