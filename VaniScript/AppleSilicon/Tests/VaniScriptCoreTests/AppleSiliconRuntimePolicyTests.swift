import Testing
@testable import VaniScriptCore

@Suite("Apple Silicon runtime policy")
struct AppleSiliconRuntimePolicyTests {
    @Test("accepts arm64 machines")
    func acceptsArm64() {
        #expect(AppleSiliconRuntimePolicy.isSupported(machineArchitecture: "arm64"))
    }

    @Test("rejects Intel machines")
    func rejectsIntel() {
        #expect(!AppleSiliconRuntimePolicy.isSupported(machineArchitecture: "x86_64"))
    }

    @Test("exposes the required architecture for build scripts")
    func requiredArchitecture() {
        #expect(AppleSiliconRuntimePolicy.requiredArchitecture == "arm64")
    }
}
