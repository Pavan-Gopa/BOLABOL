import Testing
@testable import VaniScriptCore

@Suite("App identity")
struct AppIdentityTests {
    @Test("uses the VaniScript Apple Silicon product identity")
    func productIdentity() {
        #expect(AppIdentity.displayName == "VaniScript")
        #expect(AppIdentity.bundleName == "VaniScript")
        #expect(AppIdentity.executableName == "VaniScript")
        #expect(AppIdentity.bundleIdentifier == "com.vaniscript.apple-silicon")
        #expect(AppIdentity.dataDirectoryName == "VaniScript")
        #expect(AppIdentity.minimumMacOSVersion == "14.0")
    }

    @Test("declares a native-only engine catalog")
    func nativeOnlyEngineCatalog() {
        #expect(NativeEngineCatalog.transcriptionBackend == "WhisperKit/Core ML")
        #expect(NativeEngineCatalog.polishingBackend == "MLX Swift")
        #expect(NativeEngineCatalog.hasElectronFallback == false)
        #expect(NativeEngineCatalog.hasNodeFallback == false)
    }
}
