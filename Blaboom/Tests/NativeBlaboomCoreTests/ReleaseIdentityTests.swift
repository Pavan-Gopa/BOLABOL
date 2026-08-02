import Foundation
import Testing

@Test
func releaseScriptsBuildBlaboomAppWithoutNativePrefix() throws {
    let scriptPaths = [
        "script/build_and_run.sh",
        "script/build_release_dmg.sh"
    ]

    for scriptPath in scriptPaths {
        let source = try String(contentsOfFile: scriptPath, encoding: .utf8)

        #expect(source.contains("SWIFT_PRODUCT_NAME=\"NativeBlaboom\""))
        #expect(source.contains("APP_NAME=\"Blaboom\""))
        #expect(source.contains("DISPLAY_NAME=\"Blaboom\""))
        #expect(source.contains("APP_BUNDLE=\"$"))
        #expect(source.contains("$APP_NAME.app"))
        #expect(source.contains("APP_BINARY=\"$APP_MACOS/$APP_NAME\""))
        #expect(source.contains("<string>$APP_NAME</string>"))
        #expect(!source.contains("APP_NAME=\"NativeBlaboom\""))
    }
}

@Test
func debugRunScriptBuildsAppAndWorkerProductsSeparately() throws {
    let source = try String(contentsOfFile: "script/build_and_run.sh", encoding: .utf8)

    #expect(source.contains("swift build --arch arm64 --product \"$SWIFT_PRODUCT_NAME\""))
    #expect(source.contains("swift build --arch arm64 --product \"$WORKER_NAME\""))
    #expect(!source.contains("swift build --arch arm64 --product \"$SWIFT_PRODUCT_NAME\" --product \"$WORKER_NAME\""))
}

@Test
func releaseDmgUsesBlaboomFilename() throws {
    let source = try String(contentsOfFile: "script/build_release_dmg.sh", encoding: .utf8)

    #expect(source.contains("OUTPUT_DMG=\"$DIST_DIR/Blaboom.dmg\""))
    #expect(!source.contains("OUTPUT_DMG=\"$DIST_DIR/NativeBlaboom.dmg\""))
}

@Test
func glossaryExportDefaultsUseBlaboomFilename() throws {
    let source = try String(
        contentsOfFile: "Sources/NativeBlaboom/Views/Settings/GlossarySettingsView.swift",
        encoding: .utf8
    )

    #expect(source.contains("Blaboom-glossary.json"))
    #expect(source.contains("Blaboom-glossary.csv"))
    #expect(!source.contains("NativeBlaboom-glossary"))
}

@Test
func distributedLogoLookupDoesNotUseSwiftPMModuleBundle() throws {
    let source = try String(
        contentsOfFile: "Sources/NativeBlaboom/Views/Components/BlaboomLogoView.swift",
        encoding: .utf8
    )

    #expect(source.contains("forResource: \"BLABOOM_LOGO\""))
    #expect(source.contains("subdirectory: \"Logos\""))
    #expect(!source.contains("New_Logo"))
    #expect(!source.contains("Bundle.module"))
}

@Test
func fullLogoLookupDoesNotUseSwiftPMModuleBundle() throws {
    let source = try String(
        contentsOfFile: "Sources/NativeBlaboom/Views/Components/BlaboomFullLogoView.swift",
        encoding: .utf8
    )

    #expect(source.contains("forResource: \"BLABOOM_LOGO_Full\""))
    #expect(source.contains("subdirectory: \"Logos\""))
    #expect(!source.contains("Bundle.module"))
}

@Test
func wordmarkLogoLookupDoesNotUseSwiftPMModuleBundle() throws {
    let source = try String(
        contentsOfFile: "Sources/NativeBlaboom/Views/Components/BlaboomWordmarkView.swift",
        encoding: .utf8
    )

    #expect(source.contains("forResource: \"BLABOOM_Wordmark\""))
    #expect(source.contains("subdirectory: \"Logos\""))
    #expect(!source.contains("Bundle.module"))
}

@Test
func mainWindowAndOnboardingUseNativeRoundedTitle() throws {
    let onboardingView = try String(
        contentsOfFile: "Sources/NativeBlaboom/Views/OnboardingView.swift",
        encoding: .utf8
    )
    let appSource = try String(
        contentsOfFile: "Sources/NativeBlaboom/App/NativeBlaboomApp.swift",
        encoding: .utf8
    )

    #expect(onboardingView.contains("design: .rounded"))
    #expect(appSource.contains("window.titleVisibility = .visible"))
    #expect(appSource.contains("withDesign(.rounded)"))
}

@Test
func onboardingWelcomeUsesStandaloneLogoIcon() throws {
    let onboardingView = try String(
        contentsOfFile: "Sources/NativeBlaboom/Views/OnboardingView.swift",
        encoding: .utf8
    )
    #expect(onboardingView.contains("BlaboomLogoView(size: 100)"))
    #expect(!onboardingView.contains("BlaboomFullLogoView"))
}

@Test
func statusBarIconLookupDoesNotUseSwiftPMModuleBundle() throws {
    let source = try String(
        contentsOfFile: "Sources/NativeBlaboom/App/NativeBlaboomApp.swift",
        encoding: .utf8
    )

    #expect(source.contains("named: \"BLABOOM_status_bar_icon\""))
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
