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

    #expect(source.contains("swift build --arch arm64 --product \"$SWIFT_PRODUCT_NAME\""))
    #expect(source.contains("swift build --arch arm64 --product \"$WORKER_NAME\""))
    #expect(!source.contains("swift build --arch arm64 --product \"$SWIFT_PRODUCT_NAME\" --product \"$WORKER_NAME\""))
}

@Test
func releaseDmgUsesBolabolFilename() throws {
    let source = try String(contentsOfFile: "script/build_release_dmg.sh", encoding: .utf8)

    #expect(source.contains("OUTPUT_DMG=\"$DIST_DIR/Bolabol.dmg\""))
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
func fullLogoLookupDoesNotUseSwiftPMModuleBundle() throws {
    let source = try String(
        contentsOfFile: "Sources/NativeBolabol/Views/Components/BolabolFullLogoView.swift",
        encoding: .utf8
    )

    #expect(source.contains("forResource: \"BOLABOL_LOGO_Full\""))
    #expect(source.contains("subdirectory: \"Logos\""))
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
