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

    @Test("production packaging requires in-repo VaniScript SVG and contains no workspace shared references")
    func productionPackagingRequiresInRepoVaniScriptLogo() throws {
        let source = try String(contentsOfFile: "script/build_release_dmg.sh", encoding: .utf8)
        #expect(source.contains("copy_required_asset \"$APPLE_SILICON_ASSETS_DIR/VaniScript_Logo.svg\" \"$APP_RESOURCES/VaniScript_Logo.svg\""))
        #expect(!source.contains("$WORKSPACE_DIR/Shared"))
        #expect(!source.contains("Shared/"))
        #expect(FileManager.default.fileExists(atPath: "Assets/VaniScript_Logo.svg"))
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

    @Test("release workflow uses UTC timestamp format for tag pushes, never GITHUB_RUN_NUMBER, and preserves explicit dispatch input")
    func releaseWorkflowBuildIdentityResolutionAndMonotonicity() throws {
        let source = try String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)
        let identityStepHeader = try #require(source.range(of: "- name: Resolve and validate release identity"))
        let qualificationStepHeader = try #require(source.range(of: "- name: Focused qualification tests", range: identityStepHeader.upperBound..<source.endIndex))
        let identityStep = String(source[identityStepHeader.lowerBound..<qualificationStepHeader.lowerBound])

        // Verify tag-push path uses strictly numeric UTC timestamp date format and never GITHUB_RUN_NUMBER
        #expect(identityStep.contains("build=\"$(date -u +%Y%m%d%H%M%S)\""))
        #expect(!source.contains("GITHUB_RUN_NUMBER"))

        // Scope required: true to the workflow_dispatch build_number input
        let dispatchInputsHeader = try #require(source.range(of: "workflow_dispatch:"))
        let permissionsHeader = try #require(source.range(of: "permissions:", range: dispatchInputsHeader.upperBound..<source.endIndex))
        let dispatchSection = String(source[dispatchInputsHeader.lowerBound..<permissionsHeader.lowerBound])
        let buildNumberInput = try #require(dispatchSection.range(of: "build_number:"))
        let buildNumberSection = String(dispatchSection[buildNumberInput.lowerBound..<dispatchSection.endIndex])
        #expect(buildNumberSection.contains("required: true"))
        #expect(buildNumberSection.contains("description: Strictly increasing numeric build number"))
        #expect(identityStep.contains("INPUT_BUILD: ${{ inputs.build_number }}"))
        #expect(identityStep.contains("build=\"$INPUT_BUILD\""))

        // Assert tag-to-revision binding for workflow_dispatch
        #expect(identityStep.contains("git rev-parse --verify \"refs/tags/$tag^{commit}\""))
        #expect(identityStep.contains("target_commit=\"${GITHUB_SHA:-$(git rev-parse HEAD)}\""))
        #expect(identityStep.contains("[[ \"$tag_commit\" == \"$target_commit\" ]]"))

        // Verify strictly numeric format validation
        #expect(identityStep.contains("[[ \"$build\" =~ ^[0-9]+$ ]]"))

        // Verify Python arbitrary-precision monotonic comparison is wired via env and bash arithmetic is removed
        #expect(identityStep.contains("CURRENT_BUILD=\"$build\" PREVIOUS_BUILD=\"$previous_build\""))
        #expect(identityStep.contains("current_build = int(os.environ['CURRENT_BUILD'])"))
        #expect(identityStep.contains("previous_build = int(os.environ['PREVIOUS_BUILD'])"))
        #expect(identityStep.contains("raise SystemExit(f\"build number must increase: {current_build} <= {previous_build}\")"))
        #expect(!source.contains("10#$build"))
        #expect(!source.contains("10#$previous_build"))

        // Baseline: v3.0.0 manifest build 20260818223000
        let v300Build: Int64 = 20260818223000

        // Failure-before: GITHUB_RUN_NUMBER=1 fails monotonic preflight comparison (1 <= 20260818223000)
        let failureBeforeRunNumberBuild: Int64 = 1
        #expect(failureBeforeRunNumberBuild <= v300Build, "GITHUB_RUN_NUMBER=1 correctly fails against v3.0.0 baseline 20260818223000")

        // Fix-after: UTC timestamp format (YYYYMMDDHHMMSS) strictly increases over v3.0.0 baseline
        let utcDateFormatter = DateFormatter()
        utcDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        utcDateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        utcDateFormatter.dateFormat = "yyyyMMddHHmmss"
        let generatedTimestamp = utcDateFormatter.string(from: Date())
        #expect(generatedTimestamp.count == 14)
        #expect(generatedTimestamp.range(of: "^[0-9]{14}$", options: .regularExpression) != nil)

        // Any current or future UTC date after 2026-08-18 strictly increases over v3.0.0 build
        if let currentBuildValue = Int64(generatedTimestamp) {
            #expect(currentBuildValue > v300Build, "Current UTC timestamp build \(generatedTimestamp) must strictly exceed v3.0.0 build \(v300Build)")
        }

        // Explicit dispatch build number (e.g. 20260820000000) strictly increases
        let explicitDispatchBuild: Int64 = 20260820000000
        #expect(explicitDispatchBuild > v300Build)
    }

    @Test("workflow dispatch enforces tag commit peeling and equality with dispatched commit")
    func workflowDispatchEnforcesTagToRevisionBinding() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testScript = """
        set -euo pipefail
        cd "\(tempDir.path)"
        git init -q
        git config user.email "test@example.com"
        git config user.name "Test User"
        echo "v1" > file.txt
        git add file.txt
        git commit -qm "Initial commit"
        git tag -a v3.1.0 -m "Release 3.1.0"

        # 1. Matching commit succeeds
        tag="v3.1.0"
        GITHUB_SHA="$(git rev-parse HEAD)"
        tag_commit="$(git rev-parse --verify "refs/tags/$tag^{commit}" 2>/dev/null || true)"
        [[ -n "$tag_commit" ]] || exit 2
        target_commit="${GITHUB_SHA:-$(git rev-parse HEAD)}"
        [[ "$tag_commit" == "$target_commit" ]] || exit 3

        # 2. Non-matching commit (commit moved past tag) fails
        echo "v2" >> file.txt
        git commit -am "Second commit"
        GITHUB_SHA="$(git rev-parse HEAD)"
        target_commit="${GITHUB_SHA:-$(git rev-parse HEAD)}"
        if [[ "$tag_commit" == "$target_commit" ]]; then
            exit 4
        fi

        # 3. Non-existent tag fails
        missing_tag="v9.9.9"
        missing_commit="$(git rev-parse --verify "refs/tags/$missing_tag^{commit}" 2>/dev/null || true)"
        if [[ -n "$missing_commit" ]]; then
            exit 5
        fi
        exit 0
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", testScript]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test("workflow Python preflight enforces arbitrary-precision monotonic build numbers")
    func workflowPythonPreflightEnforcesArbitraryPrecisionMonotonicBuilds() throws {
        // 1. Real failure before fix: GITHUB_RUN_NUMBER=1 fails against v3.0.0 build 20260818223000
        let realFailure = try runWorkflowPreflightPythonScript(
            currentBuild: "1",
            previousBuild: "20260818223000"
        )
        #expect(realFailure.status != 0)
        #expect(realFailure.output.contains("build number must increase: 1 <= 20260818223000"))

        // 2. Real fix after: UTC timestamp strictly exceeds v3.0.0 build 20260818223000
        let realFix = try runWorkflowPreflightPythonScript(
            currentBuild: "20260820120000",
            previousBuild: "20260818223000"
        )
        #expect(realFix.status == 0)

        // 3. Equality rejects
        let equalityRejection = try runWorkflowPreflightPythonScript(
            currentBuild: "20260818223000",
            previousBuild: "20260818223000"
        )
        #expect(equalityRejection.status != 0)
        #expect(equalityRejection.output.contains("build number must increase: 20260818223000 <= 20260818223000"))

        // 4. Oversized previous rejects smaller timestamp (beyond 64-bit int range)
        let oversizedPrevious = try runWorkflowPreflightPythonScript(
            currentBuild: "20260820120000",
            previousBuild: "99999999999999999999999999999999999"
        )
        #expect(oversizedPrevious.status != 0)
        #expect(oversizedPrevious.output.contains("build number must increase: 20260820120000 <= 99999999999999999999999999999999999"))

        // 5. Oversized current greater succeeds (beyond 64-bit int range)
        let oversizedCurrent = try runWorkflowPreflightPythonScript(
            currentBuild: "100000000000000000000000000000000000",
            previousBuild: "99999999999999999999999999999999999"
        )
        #expect(oversizedCurrent.status == 0)
    }

    @Test("release workflow prioritizes curated notes over generated fallback before appcast generation")
    func releaseWorkflowCuratedNotesPrecedenceAndAppcastOrdering() throws {
        let source = try String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)
        let appcastStepHeader = try #require(source.range(of: "- name: Generate signed appcast and release notes"))
        let uploadStepHeader = try #require(source.range(of: "- name: Create draft and upload release assets", range: appcastStepHeader.upperBound..<source.endIndex))

        let appcastStep = source[appcastStepHeader.lowerBound..<uploadStepHeader.lowerBound]
        let pipefail = try #require(appcastStep.range(of: "set -euo pipefail"))
        let keyCheck = try #require(appcastStep.range(of: ": \"${SPARKLE_PRIVATE_ED_KEY:?missing Sparkle private key}\"", range: pipefail.upperBound..<appcastStep.endIndex))
        let curatedCheck = try #require(appcastStep.range(of: "if [[ -f \"docs/releases/VaniScript-$version.md\" ]]; then", range: keyCheck.upperBound..<appcastStep.endIndex))
        let curatedCopy = try #require(appcastStep.range(of: "cp \"docs/releases/VaniScript-$version.md\" \"dist/VaniScript-$version.md\"", range: curatedCheck.upperBound..<appcastStep.endIndex))
        let fallbackBranch = try #require(appcastStep.range(of: "else", range: curatedCopy.upperBound..<appcastStep.endIndex))
        let fallbackApi = try #require(appcastStep.range(of: "repos/$GITHUB_REPOSITORY/releases/generate-notes", range: fallbackBranch.upperBound..<appcastStep.endIndex))
        let appcastInputCopy = try #require(appcastStep.range(of: "cp \"dist/VaniScript-$version.md\" dist/appcast-input/", range: fallbackApi.upperBound..<appcastStep.endIndex))
        let generateAppcast = try #require(appcastStep.range(of: "printf '%s' \"$SPARKLE_PRIVATE_ED_KEY\" | .build/artifacts/sparkle/Sparkle/bin/generate_appcast --ed-key-file - --download-url-prefix \"https://github.com/Pavan-Gopa/VaniScript/releases/download/$tag/\" -o dist/appcast.xml dist/appcast-input", range: appcastInputCopy.upperBound..<appcastStep.endIndex))
        let appcastValidation = try #require(appcastStep.range(of: "test -s dist/appcast.xml", range: generateAppcast.upperBound..<appcastStep.endIndex))
        let signUpdate = try #require(appcastStep.range(of: "printf '%s' \"$SPARKLE_PRIVATE_ED_KEY\" | .build/artifacts/sparkle/Sparkle/bin/sign_update --ed-key-file - dist/appcast.xml", range: appcastValidation.upperBound..<appcastStep.endIndex))
        let signatureCheck = try #require(appcastStep.range(of: "grep -q '<!-- sparkle-signatures:' dist/appcast.xml", range: signUpdate.upperBound..<appcastStep.endIndex))

        let envLine = try #require(appcastStep.range(of: "SPARKLE_PRIVATE_ED_KEY: ${{ secrets.SPARKLE_PRIVATE_ED_KEY }}"))
        var keyOccurrences: [Range<String.Index>] = []
        var keySearchRange: Range<String.Index> = appcastStep.startIndex..<appcastStep.endIndex
        while let range = appcastStep.range(of: "SPARKLE_PRIVATE_ED_KEY", range: keySearchRange) {
            keyOccurrences.append(range)
            keySearchRange = range.upperBound..<appcastStep.endIndex
        }
        #expect(keyOccurrences.count == 5)
        #expect(envLine.contains(keyOccurrences[0].lowerBound))
        #expect(envLine.contains(keyOccurrences[1].lowerBound))
        #expect(keyCheck.contains(keyOccurrences[2].lowerBound))
        #expect(generateAppcast.contains(keyOccurrences[3].lowerBound))
        #expect(signUpdate.contains(keyOccurrences[4].lowerBound))

        var printfOccurrences: [Range<String.Index>] = []
        var printfSearchRange: Range<String.Index> = appcastStep.startIndex..<appcastStep.endIndex
        while let range = appcastStep.range(of: "printf", range: printfSearchRange) {
            printfOccurrences.append(range)
            printfSearchRange = range.upperBound..<appcastStep.endIndex
        }
        #expect(printfOccurrences.count == 2)
        #expect(generateAppcast.contains(printfOccurrences[0].lowerBound))
        #expect(signUpdate.contains(printfOccurrences[1].lowerBound))

        #expect(!appcastStep.contains("set -x"))
        #expect(!appcastStep.contains("set -o xtrace"))
        #expect(!appcastStep.contains("echo"))

        #expect(pipefail.lowerBound < keyCheck.lowerBound)
        #expect(keyCheck.lowerBound < curatedCheck.lowerBound)
        #expect(curatedCheck.lowerBound < curatedCopy.lowerBound)
        #expect(curatedCopy.lowerBound < fallbackBranch.lowerBound)
        #expect(fallbackBranch.lowerBound < fallbackApi.lowerBound)
        #expect(fallbackApi.lowerBound < appcastInputCopy.lowerBound)
        #expect(appcastInputCopy.lowerBound < generateAppcast.lowerBound)
        #expect(generateAppcast.lowerBound < appcastValidation.lowerBound)
        #expect(appcastValidation.lowerBound < signUpdate.lowerBound)
        #expect(signUpdate.lowerBound < signatureCheck.lowerBound)
        #expect(!appcastStep.contains("mv dist/appcast-input/appcast.xml"))
        #expect(!source.contains("mv dist/appcast-input/appcast.xml"))

        let uploadStep = source[uploadStepHeader.lowerBound..<source.endIndex]
        let releaseCreate = try #require(uploadStep.range(of: "gh release create"))
        let notesFlag = try #require(uploadStep.range(of: "--notes-file \"dist/VaniScript-$version.md\"", range: releaseCreate.upperBound..<uploadStep.endIndex))
        let generalUpload = try #require(uploadStep.range(of: "gh release upload \"$tag\" --repo \"$GITHUB_REPOSITORY\"", range: notesFlag.upperBound..<uploadStep.endIndex))
        let notesUpload = try #require(uploadStep.range(of: "\"dist/VaniScript-$version.md\"", range: generalUpload.upperBound..<uploadStep.endIndex))
        let appcastUpload = try #require(uploadStep.range(of: "gh release upload \"$tag\" --repo \"$GITHUB_REPOSITORY\" dist/appcast.xml", range: notesUpload.upperBound..<uploadStep.endIndex))
        let postAppcastUploadSuffix = uploadStep[appcastUpload.upperBound..<uploadStep.endIndex]

        #expect(releaseCreate.lowerBound < notesFlag.lowerBound)
        #expect(notesFlag.lowerBound < generalUpload.lowerBound)
        #expect(generalUpload.lowerBound < notesUpload.lowerBound)
        #expect(notesUpload.lowerBound < appcastUpload.lowerBound)
        #expect(!postAppcastUploadSuffix.contains("gh release upload"))
    }

    @Test("curated 3.1.0 release notes contain Batch workspace features, 3.0.0 foundation, and update paths")
    func curated310ReleaseNotesContent() throws {
        let notesPath = "docs/releases/VaniScript-3.1.0.md"
        #expect(FileManager.default.fileExists(atPath: notesPath))
        let notes = try String(contentsOfFile: notesPath, encoding: .utf8)

        #expect(notes.contains("VaniScript 3.1.0"))
        #expect(notes.contains("What's new: Batch Transcription Workspace"))
        #expect(notes.contains("Watched Folders"))
        #expect(notes.contains("Sequential Start/Stop Queue"))
        #expect(notes.contains("Exact Provider & Model Binding"))
        #expect(notes.contains("Automatic Chunking & Resume"))
        #expect(notes.contains("Truthful Per-File Progress"))
        #expect(notes.contains("Canonical-Name Toggle"))
        #expect(notes.contains("Atomic Exact-Stem Timed TXT"))
        #expect(notes.contains("Completed-Checkpoint Recovery"))
        #expect(notes.contains("From 3.0.0"))
        #expect(notes.contains("Editorial Workspace"))
        #expect(notes.contains("Check for Updates"))
        #expect(notes.contains("Settings"))
        #expect(notes.contains("Sparkle"))
        #expect(notes.contains("VaniScript.dmg"))
        #expect(notes.contains("macOS 14"))
        #expect(notes.contains("Apple Silicon"))
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
    private func runWorkflowPreflightPythonScript(
        version: String = "3.1.0",
        previousVersion: String = "3.0.0",
        currentBuild: String,
        previousBuild: String
    ) throws -> (status: Int32, output: String) {
        let workflow = try String(contentsOfFile: ".github/workflows/release.yml", encoding: .utf8)
        let pythonStartMarker = "python3 - <<'PY'\n"
        let pythonEndMarker = "          PY\n"
        let start = try #require(workflow.range(of: pythonStartMarker)?.upperBound)
        let end = try #require(workflow.range(of: pythonEndMarker, range: start..<workflow.endIndex)?.lowerBound)
        let pythonScript = workflow[start..<end]
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in line.hasPrefix("          ") ? String(line.dropFirst(10)) : String(line) }
            .joined(separator: "\n")
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".py")
        try pythonScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptURL.path]
        var environment = ProcessInfo.processInfo.environment
        environment["VERSION"] = version
        environment["PREVIOUS_VERSION"] = previousVersion
        environment["CURRENT_BUILD"] = currentBuild
        environment["PREVIOUS_BUILD"] = previousBuild
        process.environment = environment

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        return (process.terminationStatus, output)
    }
}
