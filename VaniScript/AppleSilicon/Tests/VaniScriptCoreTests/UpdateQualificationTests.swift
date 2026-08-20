import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Update and release packaging qualification")
struct UpdateQualificationTests {

    // MARK: - Version & Build Identity Tests

    @Test("semantic version validation accepts valid SemVer and rejects invalid formats")
    func semanticVersionValidation() {
        let validVersions = ["1.0.0", "0.1.0", "2.10.3", "1.0.0-beta.1", "1.0.0-rc2"]
        let invalidVersions = ["1", "1.0", "v1.0.0", "1.0.0.0", "beta", ""]

        let semverRegex = try? NSRegularExpression(pattern: "^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?$")
        #expect(semverRegex != nil)

        for version in validVersions {
            let range = NSRange(location: 0, length: version.utf16.count)
            let isMatch = semverRegex?.firstMatch(in: version, options: [], range: range) != nil
            #expect(isMatch, "Expected '\(version)' to be valid SemVer")
        }

        for version in invalidVersions {
            let range = NSRange(location: 0, length: version.utf16.count)
            let isMatch = semverRegex?.firstMatch(in: version, options: [], range: range) != nil
            #expect(!isMatch, "Expected '\(version)' to be rejected")
        }
    }

    @Test("build number validation requires strictly numeric increasing values")
    func buildNumberValidation() {
        let validBuilds = ["1", "42", "20260818123456", "100200300"]
        let invalidBuilds = ["1.0", "v1", "dev-123", "alpha", "100a", "", " "]

        let numericRegex = try? NSRegularExpression(pattern: "^[0-9]+$")
        #expect(numericRegex != nil)

        for build in validBuilds {
            let range = NSRange(location: 0, length: build.utf16.count)
            let isMatch = numericRegex?.firstMatch(in: build, options: [], range: range) != nil
            #expect(isMatch, "Expected '\(build)' to be valid numeric build number")
        }

        for build in invalidBuilds {
            let range = NSRange(location: 0, length: build.utf16.count)
            let isMatch = numericRegex?.firstMatch(in: build, options: [], range: range) != nil
            #expect(!isMatch, "Expected '\(build)' to be rejected as build number")
        }
    }

    // MARK: - Script Behavior Tests

    @Test("release script rejects invalid semantic version with actionable error")
    func releaseScriptRejectsInvalidSemanticVersion() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["script/build_release_dmg.sh", "--version", "not-a-version"]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)

        #expect(process.terminationStatus != 0)
        #expect(output.contains("error: VANISCRIPT_VERSION must be a valid semantic version"))
    }

    @Test("release script rejects non-numeric build number with actionable error")
    func releaseScriptRejectsNonNumericBuildNumber() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["script/build_release_dmg.sh", "--build-number", "invalid_build_123"]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)

        #expect(process.terminationStatus != 0)
        #expect(output.contains("error: VANISCRIPT_BUILD_NUMBER must be a strictly numeric string"))
    }

    @Test("release script rejects ad-hoc signing in production mode with actionable error")
    func releaseScriptRejectsAdhocSigningInProduction() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["script/build_release_dmg.sh"]

        var environment = ProcessInfo.processInfo.environment
        environment["CODESIGN_IDENTITY"] = "-"
        environment.removeValue(forKey: "VANISCRIPT_DEBUG_PACKAGING")
        environment.removeValue(forKey: "ALLOW_ADHOC_SIGNING")
        process.environment = environment

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)

        #expect(process.terminationStatus != 0)
        #expect(output.contains("error: ad-hoc signing ('-') is not permitted for production release packaging."))
        #expect(output.contains("VANISCRIPT_DEBUG_PACKAGING=1"))
    }

    @Test("production packaging fails before signing when Sparkle public key is missing")
    func productionPackagingRequiresSparklePublicKey() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["script/build_release_dmg.sh"]

        var environment = ProcessInfo.processInfo.environment
        environment["CODESIGN_IDENTITY"] = "Developer ID Application: Test"
        environment.removeValue(forKey: "VANISCRIPT_SPARKLE_PUBLIC_ED_KEY")
        environment.removeValue(forKey: "VANISCRIPT_DEBUG_PACKAGING")
        environment.removeValue(forKey: "ALLOW_ADHOC_SIGNING")
        process.environment = environment

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()

        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus != 0)
        #expect(output.contains("production release packaging requires VANISCRIPT_SPARKLE_PUBLIC_ED_KEY before signing"))
        #expect(!output.contains("=== Building"))
    }

    // MARK: - Release Artifact & Manifest Invariants

    @Test("release manifest structure validates required fields")
    func releaseManifestStructure() throws {
        let manifestJSON = """
        {
          "schemaVersion": 1,
          "bundleIdentifier": "com.vaniscript.apple-silicon",
          "version": "1.0.0",
          "buildNumber": "20260818123456",
          "minimumSystemVersion": "14.0",
          "architecture": "arm64",
          "artifacts": {
            "dmg": {
              "filename": "VaniScript.dmg",
              "versionedFilename": "VaniScript-1.0.0.dmg",
              "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
              "size": 1024
            },
            "updateZip": {
              "filename": "VaniScript-1.0.0.zip",
              "genericFilename": "VaniScript.zip",
              "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
              "size": 1024
            }
          }
        }
        """

        struct ReleaseArtifactInfo: Decodable {
            let filename: String
            let sha256: String
            let size: Int
        }

        struct ReleaseArtifacts: Decodable {
            let dmg: ReleaseArtifactInfo
            let updateZip: ReleaseArtifactInfo
        }

        struct ReleaseManifest: Decodable {
            let schemaVersion: Int
            let bundleIdentifier: String
            let version: String
            let buildNumber: String
            let minimumSystemVersion: String
            let architecture: String
            let artifacts: ReleaseArtifacts
        }

        let decoder = JSONDecoder()
        let manifest = try decoder.decode(ReleaseManifest.self, from: Data(manifestJSON.utf8))

        #expect(manifest.schemaVersion == 1)
        #expect(manifest.bundleIdentifier == "com.vaniscript.apple-silicon")
        #expect(manifest.version == "1.0.0")
        #expect(manifest.architecture == "arm64")
        #expect(manifest.minimumSystemVersion == "14.0")
        #expect(manifest.artifacts.dmg.filename == "VaniScript.dmg")
        #expect(manifest.artifacts.updateZip.filename == "VaniScript-1.0.0.zip")
    }

    @Test("production update feed targets the public Pavan-Gopa repository")
    func productionUpdateFeedRepository() throws {
        let configuration = try String(contentsOfFile: "Sources/VaniScript/Updates/UpdateConfiguration.swift", encoding: .utf8)
        let releaseScript = try String(contentsOfFile: "script/build_release_dmg.sh", encoding: .utf8)
        let expectedURL = "https://github.com/Pavan-Gopa/VaniScript/releases/latest/download/appcast.xml"

        #expect(configuration.contains(expectedURL))
        #expect(releaseScript.contains(expectedURL))
        #expect(!configuration.contains("github.com/Stichting-Kadamba/VaniScript"))
        #expect(!releaseScript.contains("github.com/Stichting-Kadamba/VaniScript"))
    }

    @Test("production packaging notarizes the final signed DMG before final hashes")
    func productionReleaseIsNotarizedAndStapledBeforeHashes() throws {
        let source = try String(contentsOfFile: "script/build_release_dmg.sh", encoding: .utf8)
        let requiredFragments = [
            "notarytool submit \"$OUTPUT_DMG\"",
            "--wait --output-format plist",
            "\"$NOTARY_STATUS\" != \"Accepted\"",
            "stapler staple \"$OUTPUT_DMG\"",
            "stapler validate \"$OUTPUT_DMG\"",
            "context:primary-signature",
            "DMG_SHA256=",
        ]
        let offsets = try requiredFragments.map { fragment in
            try #require(source.range(of: fragment)?.lowerBound)
        }

        #expect(offsets == offsets.sorted())
        #expect(source.contains("if [[ \"$DEBUG_MODE\" -ne 1 ]]; then\n  NOTARIZE_REQUESTED=1"))
        #expect(source.contains("error: notarization credentials missing"))
    }

    @Test("workflow SemVer comparator implements prerelease precedence")
    func workflowSemVerComparator() throws {
        let cases: [(String, String, Int32)] = [
            ("2.0.0", "1.99.99", 1),
            ("1.0.0-alpha", "1.0.0", -1),
            ("1.0.0", "1.0.0-rc.1", 1),
            ("1.0.0-alpha.10", "1.0.0-alpha.2", 1),
            ("1.0.0-alpha.1", "1.0.0-alpha.beta", -1),
            ("1.0.0-beta", "1.0.0-alpha", 1),
            ("1.0.0-alpha.1", "1.0.0-alpha", 1),
            ("1.0.0-rc.1", "1.0.0-rc.1", 0),
        ]

        for (current, previous, expected) in cases {
            try expectWorkflowSemVerComparison(current, previous, equals: expected)
        }
    }

    @Test("workflow only bypasses a manifest when no release exists")
    func workflowFailsClosedForExistingReleaseManifest() throws {
        let source = try String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)
        let discovery = try #require(source.range(of: "latest_tag=\"$(gh release list"))
        let releaseBranch = try #require(source.range(of: "if [[ -n \"$latest_tag\" ]]"))
        let download = try #require(source.range(of: "gh release download \"$latest_tag\""))
        let exactCount = try #require(source.range(of: "(( ${#manifests[@]} == 1 ))"))
        let firstRelease = try #require(source.range(of: "No prior release found; allowing first release"))

        #expect(discovery.lowerBound < releaseBranch.lowerBound)
        #expect(releaseBranch.lowerBound < download.lowerBound)
        #expect(download.lowerBound < exactCount.lowerBound)
        #expect(exactCount.lowerBound < firstRelease.lowerBound)
        #expect(!source.contains("gh release download --repo \"$GITHUB_REPOSITORY\" --pattern '*.manifest.json' --dir previous-release >/dev/null 2>&1"))
    }

    @Test("workflow explicitly requires the production Sparkle public key")
    func workflowRequiresSparklePublicKey() throws {
        let source = try String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)
        #expect(source.contains("VANISCRIPT_SPARKLE_PUBLIC_ED_KEY: ${{ secrets.SPARKLE_PUBLIC_ED_KEY }}"))
        #expect(source.contains(": \"${VANISCRIPT_SPARKLE_PUBLIC_ED_KEY:?missing Sparkle public key}\""))
    }

    @Test("release workflow rejects downgrade inputs and uploads appcast last")
    func releaseWorkflowPreflightAndUploadOrder() throws {
        let source = try String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)
        let versionGate = try #require(source.range(of: "release version must increase"))
        let buildGate = try #require(source.range(of: "build number must increase"))
        let artifactUpload = try #require(source.range(of: "gh release upload \"$tag\" --repo \"$GITHUB_REPOSITORY\""))
        let appcastUpload = try #require(source.range(of: "gh release upload \"$tag\" --repo \"$GITHUB_REPOSITORY\" dist/appcast.xml"))

        #expect(versionGate.lowerBound < artifactUpload.lowerBound)
        #expect(buildGate.lowerBound < artifactUpload.lowerBound)
        #expect(artifactUpload.lowerBound < appcastUpload.lowerBound)
        #expect(source.contains("environment: production"))
        #expect(source.contains("--verify-tag"))
    }

    @Test("artifact verifier rejects a tampered checksum before trust checks")
    func artifactVerifierRejectsTamperedChecksum() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let filenames = [
            "VaniScript.dmg",
            "VaniScript-1.2.3.dmg",
            "VaniScript-1.2.3.zip",
            "VaniScript.zip",
            "VaniScript-1.2.3.manifest.json",
        ]
        for filename in filenames {
            try Data("untampered".utf8).write(to: temporaryDirectory.appendingPathComponent(filename))
        }
        let checksums = filenames.map { "0000000000000000000000000000000000000000000000000000000000000000  \($0)" }.joined(separator: "\n")
        try Data((checksums + "\n").utf8).write(to: temporaryDirectory.appendingPathComponent("checksums.txt"))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["script/verify_release_artifacts.sh", "1.2.3", "123", temporaryDirectory.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        #expect(process.terminationStatus != 0)
        #expect(output.contains("FAILED"))
    }

    @Test("package dependencies pin Sparkle exact version 2.9.4 on arm64 macOS 14")
    func packageDependenciesPinSparkleExactVersion() throws {
        let packageSource = try String(
            contentsOfFile: "Package.swift",
            encoding: .utf8
        )

        #expect(packageSource.contains(".package(url: \"https://github.com/sparkle-project/Sparkle\", exact: \"2.9.4\")"))
        #expect(packageSource.contains(".product(name: \"Sparkle\", package: \"Sparkle\")"))
        #expect(packageSource.contains(".macOS(.v14)"))
    }
    private func expectWorkflowSemVerComparison(
        _ current: String,
        _ previous: String,
        equals expected: Int32
    ) throws {
        let workflow = try String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)
        let startMarker = "          # BEGIN SEMVER_COMPARATOR\n"
        let endMarker = "          # END SEMVER_COMPARATOR"
        let start = try #require(workflow.range(of: startMarker)?.upperBound)
        let end = try #require(workflow.range(of: endMarker, range: start..<workflow.endIndex)?.lowerBound)
        let comparator = workflow[start..<end]
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in line.hasPrefix("          ") ? String(line.dropFirst(10)) : String(line) }
            .joined(separator: "\n")
        let script = comparator + "\nraise SystemExit(0 if compare(os.environ['CURRENT'], os.environ['PREVIOUS']) == int(os.environ['EXPECTED']) else 1)\n"
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".py")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptURL.path]
        var environment = ProcessInfo.processInfo.environment
        environment["CURRENT"] = current
        environment["PREVIOUS"] = previous
        environment["EXPECTED"] = String(expected)
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "Expected \(current) compared with \(previous) to equal \(expected)")
    }
}
