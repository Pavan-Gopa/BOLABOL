import Foundation
import Testing
@testable import NativeBolabolCore

@Test
func transcriptionBackendsBothSupportRaw() {
    #expect(TranscriptionBackend.localWhisper.supportsRawHotkeyTarget)
    #expect(TranscriptionBackend.geminiCloud.supportsRawHotkeyTarget)
    #expect(TranscriptionBackend.geminiCloud.displayName.contains("Google"))
}

@Test
func hotkeyTargetCycleIncludesRawForEveryBackend() {
    #expect(HotkeyTarget.raw.next() == .note)
    #expect(HotkeyTarget.note.next() == .x2)
    #expect(HotkeyTarget.x2.next() == .raw)
}

@Test
func transcriptionModelSettingsDecodeMissingBackendAsLocalWhisper() throws {
    var settings = TranscriptionModelSettings()
    #expect(settings.backend == .localWhisper)

    settings.backend = .geminiCloud
    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(TranscriptionModelSettings.self, from: data)
    #expect(decoded.backend == .geminiCloud)
}
