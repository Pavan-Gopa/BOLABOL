import Foundation
import NativeBlaboomCore
import Testing

@Test
func audioRecordingDefaultsLegacyDecodingToMicrophoneSource() throws {
    let json = """
    {
      "id": "00000000-0000-0000-0000-000000000100",
      "fileURL": "file:///tmp/native-blaboom-test.wav",
      "createdAt": 769392000,
      "duration": 12.5,
      "sampleRate": 48000,
      "channelCount": 1,
      "fileSizeBytes": 1024,
      "suggestedTitle": "Recorded note"
    }
    """.data(using: .utf8)!

    let recording = try JSONDecoder().decode(AudioRecording.self, from: json)

    #expect(recording.source == .microphone)
}

@Test
func audioRecordingPreservesExplicitImportedSourceWhenDecoding() throws {
    let recording = AudioRecording(
        fileURL: URL(fileURLWithPath: "/tmp/imported.wav"),
        duration: 18,
        sampleRate: 16_000,
        channelCount: 1,
        suggestedTitle: "Imported",
        source: .importedFile
    )

    let data = try JSONEncoder().encode(recording)
    let decoded = try JSONDecoder().decode(AudioRecording.self, from: data)

    #expect(decoded.source == .importedFile)
}
