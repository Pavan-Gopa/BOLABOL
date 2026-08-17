import Foundation
import Testing

@Test
func releaseScriptsBuildBolabolAppWithoutNativePrefix() throws {
    let scriptPaths = [
        "script/build_and_run.sh",
        "script/build_release_dmg.sh"
    ]

    for scriptPath in scriptPaths {
        let source = try String(contentsOfFile: scriptPath, encoding: .utf8)

        #expect(source.contains("SWIFT_PRODUCT_NAME=\"NativeBolabol\""))
        #expect(source.contains("APP_NAME=\"Bolabol\""))
        #expect(source.contains("DISPLAY_NAME=\"Bolabol\""))
        #expect(source.contains("APP_BUNDLE=\"$"))
        #expect(source.contains("$APP_NAME.app"))
        #expect(source.contains("APP_BINARY=\"$APP_MACOS/$APP_NAME\""))
        #expect(source.contains("<string>$APP_NAME</string>"))
        #expect(!source.contains("APP_NAME=\"NativeBolabol\""))
    }
}

@Test
func debugRunScriptBuildsAppAndWorkerProductsSeparately() throws {
    let source = try String(contentsOfFile: "script/build_and_run.sh", encoding: .utf8)

    #expect(source.contains("swift build -c \"$BUILD_CONFIGURATION\" --arch arm64 --product \"$SWIFT_PRODUCT_NAME\""))
    #expect(source.contains("swift build -c \"$BUILD_CONFIGURATION\" --arch arm64 --product \"$WORKER_NAME\""))
    #expect(!source.contains("swift build --arch arm64 --product \"$SWIFT_PRODUCT_NAME\" --product \"$WORKER_NAME\""))
}

@Test
func debugRunScriptEmbedsSparkleFrameworkAndRpath() throws {
    let source = try String(contentsOfFile: "script/build_and_run.sh", encoding: .utf8)

    #expect(source.contains("APP_FRAMEWORKS=\"$APP_CONTENTS/Frameworks\""))
    #expect(source.contains("embed_sparkle_framework"))
    #expect(source.contains("Sparkle.framework"))
    #expect(source.contains("ditto"))
    #expect(source.contains("install_name_tool -add_rpath \"@executable_path/../Frameworks\" \"$APP_BINARY\""))
    #expect(source.contains("otool -L \"$APP_BINARY\""))
}

@Test
func settingsSceneInjectsTranscriptionEngineStore() throws {
    let source = try String(
        contentsOfFile: "Sources/NativeBolabol/App/NativeBolabolApp.swift",
        encoding: .utf8
    )
    let settingsStart = try #require(source.range(of: "Settings {\n"))
    let settingsSource = source[settingsStart.lowerBound...]

    #expect(settingsSource.contains(".environmentObject(transcriptionEngineStore)"))
    #expect(settingsSource.contains(".environmentObject(glossaryStore)"))
    #expect(settingsSource.contains(".environmentObject(updateCoordinator)"))
}

@Test
func releaseDmgUsesBolabolFilename() throws {
    let source = try String(contentsOfFile: "script/build_release_dmg.sh", encoding: .utf8)

    #expect(source.contains("OUTPUT_DMG=\"$DIST_DIR/BOLABOL.dmg\"") || source.contains("OUTPUT_DMG=\"$DIST_DIR/Bolabol.dmg\""))
    #expect(!source.contains("OUTPUT_DMG=\"$DIST_DIR/NativeBolabol.dmg\""))
}

@Test
func glossaryExportDefaultsUseBolabolFilename() throws {
    let source = try String(
        contentsOfFile: "Sources/NativeBolabol/Views/Settings/GlossarySettingsView.swift",
        encoding: .utf8
    )

    #expect(source.contains("Bolabol-glossary.json"))
    #expect(source.contains("Bolabol-glossary.csv"))
    #expect(!source.contains("NativeBolabol-glossary"))
}

@Test
func distributedLogoLookupDoesNotUseSwiftPMModuleBundle() throws {
    let source = try String(
        contentsOfFile: "Sources/NativeBolabol/Views/Components/BolabolLogoView.swift",
        encoding: .utf8
    )

    #expect(source.contains("forResource: \"BOLABOL_LOGO\""))
    #expect(source.contains("subdirectory: \"Logos\""))
    #expect(!source.contains("New_Logo"))
    #expect(!source.contains("Bundle.module"))
}

@Test
func wordmarkLogoLookupDoesNotUseSwiftPMModuleBundle() throws {
    let source = try String(
        contentsOfFile: "Sources/NativeBolabol/Views/Components/BolabolWordmarkView.swift",
        encoding: .utf8
    )

    #expect(source.contains("forResource: \"BOLABOL_Wordmark\""))
    #expect(source.contains("subdirectory: \"Logos\""))
    #expect(!source.contains("Bundle.module"))
}

@Test
func mainWindowAndOnboardingUseNativeRoundedTitle() throws {
    let onboardingView = try String(
        contentsOfFile: "Sources/NativeBolabol/Views/OnboardingView.swift",
        encoding: .utf8
    )
    let appSource = try String(
        contentsOfFile: "Sources/NativeBolabol/App/NativeBolabolApp.swift",
        encoding: .utf8
    )

    #expect(onboardingView.contains("design: .rounded"))
    #expect(appSource.contains("window.titleVisibility = .visible"))
    #expect(appSource.contains("withDesign(.rounded)"))
}

@Test
func onboardingWelcomeUsesStandaloneLogoIcon() throws {
    let onboardingView = try String(
        contentsOfFile: "Sources/NativeBolabol/Views/OnboardingView.swift",
        encoding: .utf8
    )
    #expect(onboardingView.contains("BolabolLogoView(size: 100)"))
    #expect(!onboardingView.contains("BolabolFullLogoView"))
}

@Test
func statusBarIconLookupDoesNotUseSwiftPMModuleBundle() throws {
    let source = try String(
        contentsOfFile: "Sources/NativeBolabol/App/NativeBolabolApp.swift",
        encoding: .utf8
    )

    #expect(source.contains("named: \"BOLABOL_status_bar_icon\""))
    #expect(source.contains("subdirectory: \"Logos\""))
    #expect(!source.contains("New_Logo"))
    #expect(!source.contains("trayTemplate"))
    #expect(!source.contains("Bundle.module"))
}

@Test
func buildScriptsPackageOnlyCanonicalLogoDirectory() throws {
    for scriptPath in ["script/build_and_run.sh", "script/build_release_dmg.sh"] {
        let source = try String(contentsOfFile: scriptPath, encoding: .utf8)

        #expect(source.contains("Resources/Logos/$svg_name"))
        #expect(source.contains("APP_LOGOS=\"$APP_RESOURCES/Logos\""))
        #expect(!source.contains("New_Logo"))
        #expect(!source.contains("trayTemplate"))
    }
}

@Test
func releaseDmgEmbedsSwiftCompatibilityRuntime() throws {
    let source = try String(contentsOfFile: "script/build_release_dmg.sh", encoding: .utf8)

    #expect(source.contains("APP_FRAMEWORKS=\"$APP_CONTENTS/Frameworks\""))
    #expect(source.contains("xcrun swift-stdlib-tool --print"))
    #expect(source.contains("cp \"$swift_library\" \"$APP_FRAMEWORKS/\""))
    #expect(source.contains("@executable_path/../Frameworks/libswiftCompatibilitySpan.dylib"))
    #expect(source.contains("install_name_tool -delete_rpath \"$xcode_swift62_rpath\""))
    #expect(source.contains("codesign_release \"$dylib\""))
}

@Test
func releaseDmgEmbedsSparkleFrameworkAndFeedConfiguration() throws {
    let source = try String(contentsOfFile: "script/build_release_dmg.sh", encoding: .utf8)

    #expect(source.contains("APP_VERSION=\"${APP_VERSION:-1.0.5}\""))
    #expect(source.contains("RELEASE_BUILD"))
    #expect(source.contains("embed_sparkle_framework"))
    #expect(source.contains("Sparkle.framework"))
    #expect(source.contains("ditto"))
    #expect(source.contains("otool -L"))
    #expect(source.contains("<key>SUFeedURL</key>"))
    #expect(source.contains("<key>SUEnableAutomaticChecks</key>"))
    #expect(source.contains("<key>SUScheduledCheckInterval</key>"))
    #expect(source.contains("21600"))
    #expect(source.contains("<key>SUAutomaticallyUpdate</key>"))
    #expect(source.contains("<key>SURequireSignedFeed</key>"))
    #expect(source.contains("<key>SUVerifyUpdateBeforeExtraction</key>"))
}

@Test
func singleUpdateCoordinatorOwnershipInNativeBolabolApp() throws {
    let source = try String(
        contentsOfFile: "Sources/NativeBolabol/App/NativeBolabolApp.swift",
        encoding: .utf8
    )

    // Exactly one @StateObject instantiation of UpdateCoordinator.live()
    let matches = source.components(separatedBy: "UpdateCoordinator.live()")
    #expect(matches.count == 2, "Expected exactly 1 call site for UpdateCoordinator.live(), found \(matches.count - 1)")

    #expect(source.contains("@StateObject private var updateCoordinator = UpdateCoordinator.live()"))
    #expect(!source.contains("updateCoordinator ?? UpdateCoordinator.live()"))
}

@Test
func generateAppcastScriptFailsClosedWithoutRequiredInputs() throws {
    let source = try String(contentsOfFile: "script/generate_update_appcast.sh", encoding: .utf8)

    #expect(source.contains("Error: Release DMG not found"))
    #expect(source.contains("Error: Sparkle tool 'generate_appcast' not found"))
    #expect(source.contains("Error: No Sparkle Ed25519 private key or keychain account specified"))
    #expect(source.contains("generate_appcast"))
    #expect(source.contains("--download-url-prefix"))
    #expect(source.contains("--ed-key-file"))
    #expect(source.contains("--account"))
    #expect(!source.contains("KEY_ARGS=(-f"))
    #expect(!source.contains("--keychain-account"))
    #expect(source.contains("set -euo pipefail"))
    #expect(source.contains("sparkle:edSignature"))
}

@Test
func checkUpdaterReleaseScriptValidatesMountedDmgAndSignatures() throws {
    let source = try String(contentsOfFile: "script/check_updater_release.sh", encoding: .utf8)

    #expect(source.contains("hdiutil attach"))
    #expect(source.contains("com.bolabol.app"))
    #expect(source.contains("https://raw.githubusercontent.com/Pavan-Gopa/BOLABOL/main/Bolabol/appcast.xml"))
    #expect(source.contains("21600"))
    #expect(source.contains("Sparkle.framework"))
    #expect(source.contains("otool -L"))
    #expect(source.contains("codesign --verify --deep --strict"))
    #expect(source.contains("spctl -a -vv --type execute \"$APP_PATH\""))
    #expect(source.contains("spctl -a -vv --type install \"$DMG_PATH\""))
    #expect(source.contains("xcrun stapler validate \"$DMG_PATH\""))
    #expect(!source.contains("xcrun stapler validate \"$APP_PATH\""))
    #expect(!source.contains("spctl -a -vv --type execute \"$APP_PATH\" 2>&1 || true"))
    #expect(!source.contains("xcrun stapler validate \"$DMG_PATH\" 2>&1 || true"))
    #expect(source.contains("Error: SUPublicEDKey is missing or empty"))

    // Appcast XML mandatory validation assertions
    #expect(source.contains("Error: Both DMG path and Appcast XML path arguments are required."))
    #expect(source.contains("Error: Appcast XML path argument is required."))
    #expect(source.contains("Error: Appcast XML file '$APPCAST_PATH' not found."))
    #expect(source.contains("xmllint --noout"))
    #expect(source.contains("Error: Required native XML validator 'xmllint' is not available."))
    #expect(source.contains("xmlns:sparkle="))
    #expect(source.contains("<!-- sparkle-signatures:"))
    #expect(source.contains("Error: Appcast is missing mandatory Sparkle signed-feed comment block (<!-- sparkle-signatures:)."))
    #expect(source.contains("Error: Sparkle signed-feed block is missing non-empty 'edSignature:'."))
    #expect(source.contains("Error: Sparkle signed-feed block is missing valid numeric 'length:'."))
    #expect(source.contains("Error: Appcast sparkle:version '$APPCAST_BUILD' does not match mounted app CFBundleVersion '$VERSION_BUILD'."))
    #expect(source.contains("Error: Appcast sparkle:shortVersionString '$APPCAST_SHORT_VERSION' does not match mounted app CFBundleShortVersionString '$VERSION_SHORT'."))
    #expect(source.contains("Error: Appcast enclosure is missing required EdDSA signature (sparkle:edSignature)."))
    #expect(source.contains("Error: Appcast enclosure length '$ENC_LEN' does not match exact DMG byte size '$DMG_SIZE'."))
    #expect(source.contains("Error: Appcast enclosure URL contains forbidden mutable 'latest/download'."))
    #expect(source.contains("releases/download/v${VERSION_SHORT}/BOLABOL.dmg"))
}

@Test
func publishUpdateScriptValidatesSemverAndReleasePipeline() throws {
    let source = try String(contentsOfFile: "script/publish_update.sh", encoding: .utf8)

    #expect(source.contains("^[0-9]+\\.[0-9]+\\.[0-9]+"))
    #expect(source.contains("RELEASE_BUILD=1"))
    #expect(source.contains("NOTARIZE=1"))
    #expect(source.contains("AUTO_COMMIT_FEED=\"${AUTO_COMMIT_FEED:-1}\""))
    #expect(source.contains("VERIFY_REMOTE_HTTPS=\"${VERIFY_REMOTE_HTTPS:-1}\""))
    #expect(source.contains("Error: Cannot verify remote HTTPS feed when feed deployment (AUTO_COMMIT_FEED) is disabled. Set VERIFY_REMOTE_HTTPS=0 for local-only dry runs."))
    #expect(source.contains("check_updater_release.sh"))
    #expect(source.contains("generate_update_appcast.sh"))
    #expect(source.contains("LOCAL_SHA256=\"$(shasum -a 256 \"$DIST_DIR/BOLABOL.dmg\""))
    #expect(source.contains("gh release create"))
    #expect(source.contains("gh release delete \"$TAG_NAME\" --yes"))
    #expect(source.contains("gh release edit \"$TAG_NAME\" --draft=false"))
    #expect(source.contains("gh release view \"$TAG_NAME\" --json tagName,isDraft,assets"))
    #expect(source.contains("--jq"))
    #expect(source.contains("Error: GitHub CLI ('gh') is required to publish updates but was not found in PATH."))
    #expect(source.contains("Error: Failed to verify published GitHub release '$TAG_NAME'."))
    #expect(source.contains("Error: GitHub release '$TAG_NAME' is still in draft state after publishing (isDraft=$RELEASE_IS_DRAFT)."))
    #expect(source.contains("Error: GitHub release tag mismatch: expected '$TAG_NAME', got '$VIEW_TAG_NAME'."))
    #expect(source.contains("Error: Published release '$TAG_NAME' is missing required asset 'BOLABOL.dmg'."))
    #expect(source.contains("Error: Published release '$TAG_NAME' asset 'BOLABOL.dmg' is missing required sha256 digest."))
    #expect(source.contains("Error: GitHub asset digest mismatch for BOLABOL.dmg."))
    #expect(source.contains("FEED_DEST=\"$GIT_TOPLEVEL/Bolabol/appcast.xml\""))
    #expect(source.contains("FEED_DEST=\"$ROOT_DIR/appcast.xml\""))
    #expect(source.contains("DRAFT_ONLY"))
    #expect(source.contains("PUBLIC_ASSET_URL=\"https://github.com/Pavan-Gopa/BOLABOL/releases/download/$TAG_NAME/BOLABOL.dmg\""))
    #expect(source.contains("RAW_FEED_URL=\"https://raw.githubusercontent.com/Pavan-Gopa/BOLABOL/main/Bolabol/appcast.xml\""))
}

@Test
func publishUpdateScriptContainsNoPythonRuntimeDependency() throws {
    let source = try String(contentsOfFile: "script/publish_update.sh", encoding: .utf8)
    let lowercased = source.lowercased()

    #expect(!lowercased.contains("python"))
    #expect(!lowercased.contains("python3"))
    #expect(!lowercased.contains("import json"))
    #expect(!lowercased.contains("import sys"))
}

@Test
func buildReleaseDmgFailsClosedWhenNotarizeRequestedWithoutScript() throws {
    let source = try String(contentsOfFile: "script/build_release_dmg.sh", encoding: .utf8)

    #expect(source.contains("Error: script/notarize_dmg.sh not found but NOTARIZE=1 was requested."))
    #expect(!source.contains("warning: script/notarize_dmg.sh not found. Skipping notarization submission."))
}

@Test
func notarizeDmgScriptStaplesAndValidatesDmgOnly() throws {
    let source = try String(contentsOfFile: "script/notarize_dmg.sh", encoding: .utf8)

    #expect(source.contains("xcrun stapler staple \"$DMG_PATH\""))
    #expect(source.contains("xcrun stapler validate \"$DMG_PATH\""))
    #expect(source.contains("spctl -a -vv -t install \"$DMG_PATH\""))
    #expect(!source.contains("xcrun stapler staple \"$ROOT_DIR/dist/release/Bolabol.app\""))
    #expect(!source.contains("Stapling App Bundle..."))
}

@Test
func checkUpdaterReleaseFailsClosedOnMissingArgumentsOrFiles() throws {
    func runScript(args: [String]) -> (exitCode: Int32, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["script/check_updater_release.sh"] + args
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()
        try? process.run()
        process.waitUntilExit()
        let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, stderr)
    }

    // 1. Missing both arguments
    let res0 = runScript(args: [])
    #expect(res0.exitCode != 0)
    #expect(res0.stderr.contains("Both DMG path and Appcast XML path arguments are required"))

    // 2. Missing appcast argument
    let res1 = runScript(args: ["dist/BOLABOL.dmg"])
    #expect(res1.exitCode != 0)
    #expect(res1.stderr.contains("Both DMG path and Appcast XML path arguments are required"))

    // 3. Nonexistent DMG file
    let res2 = runScript(args: ["dist/nonexistent_dmg_for_test.dmg", "dist/appcast.xml"])
    #expect(res2.exitCode != 0)
    #expect(res2.stderr.contains("Release DMG 'dist/nonexistent_dmg_for_test.dmg' not found"))

    // 4. Existing dummy DMG but nonexistent Appcast file
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dummyDmg = tempDir.appendingPathComponent("dummy.dmg")
    FileManager.default.createFile(atPath: dummyDmg.path, contents: Data("test".utf8))

    let res3 = runScript(args: [dummyDmg.path, "dist/nonexistent_appcast_for_test.xml"])
    #expect(res3.exitCode != 0)
    #expect(res3.stderr.contains("Appcast XML file 'dist/nonexistent_appcast_for_test.xml' not found"))
}
@Test
func publishUpdateFailsClosedWithoutRequiredInputs() throws {
    func runScript(args: [String], env: [String: String]? = nil) -> (exitCode: Int32, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["script/publish_update.sh"] + args
        if let env {
            process.environment = env
        }
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()
        try? process.run()
        process.waitUntilExit()
        let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, stderr)
    }

    // 1. Missing version argument
    let res0 = runScript(args: [])
    #expect(res0.exitCode != 0)
    #expect(res0.stderr.contains("Usage:"))

    // 2. Invalid semver
    let res1 = runScript(args: ["invalid-version"])
    #expect(res1.exitCode != 0)
    #expect(res1.stderr.contains("not a valid semantic version"))

    // 3. Valid semver but missing SPARKLE_PUBLIC_ED_KEY (with ALLOW_DIRTY=1)
    var baseEnv = ProcessInfo.processInfo.environment
    baseEnv["ALLOW_DIRTY"] = "1"
    baseEnv.removeValue(forKey: "SPARKLE_PUBLIC_ED_KEY")
    let res2 = runScript(args: ["1.0.5"], env: baseEnv)
    #expect(res2.exitCode != 0)
    #expect(res2.stderr.contains("SPARKLE_PUBLIC_ED_KEY environment variable is required"))

    // 4. Missing gh tool in PATH (with SPARKLE_PUBLIC_ED_KEY and ALLOW_DIRTY=1)
    var noGhEnv = baseEnv
    noGhEnv["SPARKLE_PUBLIC_ED_KEY"] = "dummyKeyBase64=="
    noGhEnv["PATH"] = "/usr/bin:/bin" // standard paths without gh
    let res3 = runScript(args: ["1.0.5"], env: noGhEnv)
    #expect(res3.exitCode != 0)
    #expect(res3.stderr.contains("GitHub CLI ('gh') is required"))
}

@Test
func publishUpdateFailsClosedWhenFeedDeploymentDisabledWithRemoteHttpsVerification() throws {
    func runScript(args: [String], env: [String: String]? = nil) -> (exitCode: Int32, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["script/publish_update.sh"] + args
        if let env {
            process.environment = env
        }
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()
        try? process.run()
        process.waitUntilExit()
        let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, stderr)
    }

    var env = ProcessInfo.processInfo.environment
    env["ALLOW_DIRTY"] = "1"
    env["AUTO_COMMIT_FEED"] = "0"
    env["VERIFY_REMOTE_HTTPS"] = "1"
    let res = runScript(args: ["1.0.5"], env: env)
    #expect(res.exitCode != 0)
    #expect(res.stderr.contains("Cannot verify remote HTTPS feed when feed deployment (AUTO_COMMIT_FEED) is disabled"))
}

@Test
func checkUpdaterReleaseSignedFeedValidationRejectsMissingOrMalformedBlock() throws {
    func runValidationScript(appcastContent: String) -> (exitCode: Int32, stdout: String, stderr: String) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tempAppcast = tempDir.appendingPathComponent("appcast.xml")
        try? appcastContent.write(to: tempAppcast, atomically: true, encoding: .utf8)

        // Execute the exact Sparkle signed-feed block extraction snippet from check_updater_release.sh
        let inlineScript = """
        APPCAST_PATH="\(tempAppcast.path)"
        if ! grep -q "xmlns:sparkle=" "$APPCAST_PATH"; then
          echo "Error: Appcast is missing Sparkle XML namespace declaration (xmlns:sparkle)." >&2
          exit 1
        fi
        if ! grep -q "<!-- sparkle-signatures:" "$APPCAST_PATH"; then
          echo "Error: Appcast is missing mandatory Sparkle signed-feed comment block (<!-- sparkle-signatures:)." >&2
          exit 1
        fi
        SPARKLE_SIG_BLOCK="$(sed -n '/<!-- sparkle-signatures:/,/-->/p' "$APPCAST_PATH")"
        if [[ -z "$SPARKLE_SIG_BLOCK" ]]; then
          echo "Error: Appcast is missing mandatory Sparkle signed-feed comment block (<!-- sparkle-signatures:)." >&2
          exit 1
        fi
        FEED_ED_SIG="$(echo "$SPARKLE_SIG_BLOCK" | grep -E 'edSignature:[[:space:]]*[A-Za-z0-9+/=]+' | sed -E 's/.*edSignature:[[:space:]]*([A-Za-z0-9+/=]+).*/\\1/' | tr -d '\\r\\n[:space:]' || true)"
        if [[ -z "$FEED_ED_SIG" ]]; then
          echo "Error: Sparkle signed-feed block is missing non-empty 'edSignature:'." >&2
          exit 1
        fi
        FEED_SIG_LEN="$(echo "$SPARKLE_SIG_BLOCK" | grep -E 'length:[[:space:]]*[0-9]+' | sed -E 's/.*length:[[:space:]]*([0-9]+).*/\\1/' | tr -d '\\r\\n[:space:]' || true)"
        if [[ -z "$FEED_SIG_LEN" || ! "$FEED_SIG_LEN" =~ ^[0-9]+$ || "$FEED_SIG_LEN" -le 0 ]]; then
          echo "Error: Sparkle signed-feed block is missing valid numeric 'length:'." >&2
          exit 1
        fi
        echo "VALID_FEED_SIG: $FEED_ED_SIG ($FEED_SIG_LEN bytes)"
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", inlineScript]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try? process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }

    // 1. Missing xmlns:sparkle
    let xmlNoNs = "<rss><channel><item></item></channel></rss>"
    let res1 = runValidationScript(appcastContent: xmlNoNs)
    #expect(res1.exitCode != 0)
    #expect(res1.stderr.contains("Appcast is missing Sparkle XML namespace declaration"))

    // 2. Missing <!-- sparkle-signatures:
    let xmlNoSigBlock = """
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel><item></item></channel>
    </rss>
    """
    let res2 = runValidationScript(appcastContent: xmlNoSigBlock)
    #expect(res2.exitCode != 0)
    #expect(res2.stderr.contains("Appcast is missing mandatory Sparkle signed-feed comment block"))

    // 3. Present block but missing edSignature:
    let xmlNoEdSig = """
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel><item></item></channel>
    </rss>
    <!-- sparkle-signatures:
    length: 123456
    -->
    """
    let res3 = runValidationScript(appcastContent: xmlNoEdSig)
    #expect(res3.exitCode != 0)
    #expect(res3.stderr.contains("Sparkle signed-feed block is missing non-empty 'edSignature:'."))

    // 4. Present block but missing/invalid length:
    let xmlNoLength = """
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel><item></item></channel>
    </rss>
    <!-- sparkle-signatures:
    edSignature: dGhpc2lzYXNpZ25hdHVyZQ==
    length: notanumber
    -->
    """
    let res4 = runValidationScript(appcastContent: xmlNoLength)
    #expect(res4.exitCode != 0)
    #expect(res4.stderr.contains("Sparkle signed-feed block is missing valid numeric 'length:'."))

    // 5. Valid signed-feed block
    let xmlValid = """
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel><item></item></channel>
    </rss>
    <!-- sparkle-signatures:
    edSignature: dGhpc2lzYXNpZ25hdHVyZQ==
    length: 123456
    -->
    """
    let res5 = runValidationScript(appcastContent: xmlValid)
    #expect(res5.exitCode == 0)
    #expect(res5.stdout.contains("VALID_FEED_SIG: dGhpc2lzYXNpZ25hdHVyZQ== (123456 bytes)"))
}

@Test
func publishUpdateGitHubReleaseVerificationRejectsDraftAndMismatchedState() throws {
    func runVerification(tagName: String, localSha: String, releaseInfo: String) -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", """
        set -euo pipefail
        TAG_NAME="$1"
        LOCAL_SHA256="$2"
        RELEASE_VIEW_INFO="$3"

        if [[ -z "$RELEASE_VIEW_INFO" ]]; then
          echo "Error: Failed to verify published GitHub release '$TAG_NAME'." >&2
          exit 1
        fi

        VIEW_TAG_NAME=""
        RELEASE_IS_DRAFT=""
        DMG_ASSET_COUNT=""
        RELEASE_ASSET_DIGEST=""
        IFS=$'\\t' read -r VIEW_TAG_NAME RELEASE_IS_DRAFT DMG_ASSET_COUNT RELEASE_ASSET_DIGEST <<< "$RELEASE_VIEW_INFO"

        if [[ "$RELEASE_IS_DRAFT" != "false" ]]; then
          echo "Error: GitHub release '$TAG_NAME' is still in draft state after publishing (isDraft=$RELEASE_IS_DRAFT)." >&2
          exit 1
        fi

        if [[ "$VIEW_TAG_NAME" != "$TAG_NAME" ]]; then
          echo "Error: GitHub release tag mismatch: expected '$TAG_NAME', got '$VIEW_TAG_NAME'." >&2
          exit 1
        fi

        if [[ -z "$DMG_ASSET_COUNT" || "$DMG_ASSET_COUNT" -lt 1 ]]; then
          echo "Error: Published release '$TAG_NAME' is missing required asset 'BOLABOL.dmg'." >&2
          exit 1
        fi

        CLEAN_RELEASE_DIGEST="${RELEASE_ASSET_DIGEST#sha256:}"
        CLEAN_RELEASE_DIGEST="${CLEAN_RELEASE_DIGEST#SHA256:}"
        CLEAN_RELEASE_DIGEST="$(echo "$CLEAN_RELEASE_DIGEST" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
        CLEAN_LOCAL_SHA="$(echo "$LOCAL_SHA256" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"

        if [[ -z "$CLEAN_RELEASE_DIGEST" ]]; then
          echo "Error: Published release '$TAG_NAME' asset 'BOLABOL.dmg' is missing required sha256 digest." >&2
          exit 1
        fi

        if [[ "$CLEAN_RELEASE_DIGEST" != "$CLEAN_LOCAL_SHA" ]]; then
          echo "Error: GitHub asset digest mismatch for BOLABOL.dmg." >&2
          exit 1
        fi

        echo "=== GitHub release $TAG_NAME published and verified successfully ==="
        """, "bash", tagName, localSha, releaseInfo]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try? process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }

    let expectedTag = "v1.0.5"
    let expectedSha = "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"

    // 1. Successful verification
    let res0 = runVerification(tagName: expectedTag, localSha: expectedSha, releaseInfo: "\(expectedTag)\tfalse\t1\tsha256:\(expectedSha)")
    #expect(res0.exitCode == 0)
    #expect(res0.stdout.contains("=== GitHub release v1.0.5 published and verified successfully ==="))

    // 2. Draft release state fails closed
    let res1 = runVerification(tagName: expectedTag, localSha: expectedSha, releaseInfo: "\(expectedTag)\ttrue\t1\tsha256:\(expectedSha)")
    #expect(res1.exitCode != 0)
    #expect(res1.stderr.contains("is still in draft state after publishing (isDraft=true)"))

    // 3. Tag mismatch fails closed
    let res2 = runVerification(tagName: expectedTag, localSha: expectedSha, releaseInfo: "v1.0.4\tfalse\t1\tsha256:\(expectedSha)")
    #expect(res2.exitCode != 0)
    #expect(res2.stderr.contains("GitHub release tag mismatch: expected 'v1.0.5', got 'v1.0.4'"))

    // 4. Missing BOLABOL.dmg asset fails closed
    let res3 = runVerification(tagName: expectedTag, localSha: expectedSha, releaseInfo: "\(expectedTag)\tfalse\t0\t")
    #expect(res3.exitCode != 0)
    #expect(res3.stderr.contains("missing required asset 'BOLABOL.dmg'"))

    // 5. Missing digest fails closed
    let res4 = runVerification(tagName: expectedTag, localSha: expectedSha, releaseInfo: "\(expectedTag)\tfalse\t1\t")
    #expect(res4.exitCode != 0)
    #expect(res4.stderr.contains("missing required sha256 digest"))

    // 6. Mismatched digest fails closed
    let res5 = runVerification(tagName: expectedTag, localSha: expectedSha, releaseInfo: "\(expectedTag)\tfalse\t1\tsha256:0000000000000000000000000000000000000000000000000000000000000000")
    #expect(res5.exitCode != 0)
    #expect(res5.stderr.contains("GitHub asset digest mismatch for BOLABOL.dmg"))
    // 7. Empty / failed release view output fails closed
    let res6 = runVerification(tagName: expectedTag, localSha: expectedSha, releaseInfo: "")
    #expect(res6.exitCode != 0)
    #expect(res6.stderr.contains("Failed to verify published GitHub release 'v1.0.5'"))
}
