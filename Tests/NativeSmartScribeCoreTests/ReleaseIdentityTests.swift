import Foundation
import Testing

@Test
func releaseScriptsBuildSmartScribeAppWithoutNativePrefix() throws {
    let scriptPaths = [
        "script/build_and_run.sh",
        "script/build_release_dmg.sh"
    ]

    for scriptPath in scriptPaths {
        let source = try String(contentsOfFile: scriptPath, encoding: .utf8)

        #expect(source.contains("SWIFT_PRODUCT_NAME=\"NativeSmartScribe\""))
        #expect(source.contains("APP_NAME=\"SmartScribe\""))
        #expect(source.contains("DISPLAY_NAME=\"SmartScribe\""))
        #expect(source.contains("APP_BUNDLE=\"$"))
        #expect(source.contains("$APP_NAME.app"))
        #expect(source.contains("APP_BINARY=\"$APP_MACOS/$APP_NAME\""))
        #expect(source.contains("<string>$APP_NAME</string>"))
        #expect(!source.contains("APP_NAME=\"NativeSmartScribe\""))
    }
}

@Test
func releaseDmgUsesSmartScribeFilename() throws {
    let source = try String(contentsOfFile: "script/build_release_dmg.sh", encoding: .utf8)

    #expect(source.contains("OUTPUT_DMG=\"$DIST_DIR/SmartScribe.dmg\""))
    #expect(!source.contains("OUTPUT_DMG=\"$DIST_DIR/NativeSmartScribe.dmg\""))
}

@Test
func glossaryExportDefaultsUseSmartScribeFilename() throws {
    let source = try String(
        contentsOfFile: "Sources/NativeSmartScribe/Views/Settings/GlossarySettingsView.swift",
        encoding: .utf8
    )

    #expect(source.contains("SmartScribe-glossary.json"))
    #expect(source.contains("SmartScribe-glossary.csv"))
    #expect(!source.contains("NativeSmartScribe-glossary"))
}

@Test
func distributedLogoLookupDoesNotUseSwiftPMModuleBundle() throws {
    let source = try String(
        contentsOfFile: "Sources/NativeSmartScribe/Views/Components/SmartScribeLogoView.swift",
        encoding: .utf8
    )

    #expect(source.contains("Bundle.main.url(forResource: \"New_Logo\", withExtension: \"svg\")"))
    #expect(!source.contains("Bundle.module"))
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
