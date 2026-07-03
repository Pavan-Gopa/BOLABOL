import AppKit
import AVFoundation
import NativeSmartScribeCore

@MainActor
final class AudioCuePlayer {
    static let shared = AudioCuePlayer()

    enum Cue {
        case start
        case finish

        var soundName: String {
            switch self {
            case .start:
                "Tink"
            case .finish:
                "Bottle"
            }
        }

        fileprivate var tone: Tone {
            switch self {
            case .start:
                Tone(frequencies: [659.25, 987.77], duration: 0.28)
            case .finish:
                Tone(frequencies: [523.25, 783.99], duration: 0.36)
            }
        }
    }

    private var players: [Cue: AVAudioPlayer] = [:]
    private var sounds: [Cue: NSSound] = [:]
    private var processes: [Cue: Process] = [:]
    private var cueFiles: [Cue: URL] = [:]

    func play(_ cue: Cue, settings: OverlayHUDSettings) {
        Self.appendDebugLog("play requested cue=\(cue.soundName) enabled=\(settings.soundEnabled) volume=\(settings.volume)")
        guard settings.soundEnabled else { return }

        if playWithAFPlay(cue, volume: settings.volume) {
            Self.appendDebugLog("play succeeded via afplay cue=\(cue.soundName)")
            return
        }

        do {
            let player = try player(for: cue)
            player.stop()
            player.currentTime = 0
            player.volume = Float(settings.volume)
            if player.play() {
                Self.appendDebugLog("play succeeded via AVAudioPlayer cue=\(cue.soundName)")
                return
            }
            NativeSmartScribeLog.hotkey.warning("AVAudioPlayer refused cue=\(cue.soundName, privacy: .public)")
            Self.appendDebugLog("AVAudioPlayer refused cue=\(cue.soundName)")
        } catch {
            NativeSmartScribeLog.hotkey.error("Audio cue failed cue=\(cue.soundName, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            Self.appendDebugLog("AVAudioPlayer error cue=\(cue.soundName) error=\(error.localizedDescription)")
        }

        if let sound = nsSound(for: cue) {
            sound.stop()
            sound.volume = Float(settings.volume)
            if sound.play() {
                Self.appendDebugLog("play succeeded via NSSound cue=\(cue.soundName)")
                return
            }
            NativeSmartScribeLog.hotkey.warning("NSSound refused cue=\(cue.soundName, privacy: .public)")
            Self.appendDebugLog("NSSound refused cue=\(cue.soundName)")
        }
        Self.appendDebugLog("all cue transports failed; falling back to beep cue=\(cue.soundName)")
        NSSound.beep()
    }

    private func player(for cue: Cue) throws -> AVAudioPlayer {
        if let player = players[cue] {
            return player
        }

        let player = try AVAudioPlayer(data: Self.wavData(for: cue.tone))
        player.prepareToPlay()
        players[cue] = player
        return player
    }

    private func nsSound(for cue: Cue) -> NSSound? {
        if let sound = sounds[cue] {
            return sound
        }

        let sound = NSSound(contentsOf: soundURL(for: cue), byReference: true)
            ?? NSSound(named: NSSound.Name(cue.soundName))
        sounds[cue] = sound
        return sound
    }

    private func soundURL(for cue: Cue) -> URL {
        URL(fileURLWithPath: "/System/Library/Sounds")
            .appendingPathComponent(cue.soundName)
            .appendingPathExtension("aiff")
    }

    private func playWithAFPlay(_ cue: Cue, volume: Double) -> Bool {
        do {
            let url = try cueFileURL(for: cue)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            process.arguments = ["-v", String(format: "%.3f", volume), url.path]
            process.terminationHandler = { [weak self] _ in
                Task { @MainActor in
                    Self.appendDebugLog("afplay terminated cue=\(cue.soundName) status=\(process.terminationStatus)")
                    self?.processes[cue] = nil
                }
            }

            processes[cue]?.terminate()
            try process.run()
            processes[cue] = process
            NativeSmartScribeLog.hotkey.info("Started afplay cue=\(cue.soundName, privacy: .public) volume=\(volume, privacy: .public)")
            Self.appendDebugLog("afplay started cue=\(cue.soundName) volume=\(volume) pid=\(process.processIdentifier)")
            return true
        } catch {
            NativeSmartScribeLog.hotkey.error("afplay cue failed cue=\(cue.soundName, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            Self.appendDebugLog("afplay error cue=\(cue.soundName) error=\(error.localizedDescription)")
            return false
        }
    }

    private func cueFileURL(for cue: Cue) throws -> URL {
        if let url = cueFiles[cue] {
            return url
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NativeSmartScribeAudioCues", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(cue.soundName).appendingPathExtension("wav")
        try Self.wavData(for: cue.tone).write(to: url, options: .atomic)
        cueFiles[cue] = url
        return url
    }

    private static func appendDebugLog(_ line: String) {
        let entry = "\(Date().ISO8601Format()) \(line)\n"
        do {
            let url = try debugLogURL()
            let data = Data(entry.utf8)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            NativeSmartScribeLog.hotkey.error("HUD audio debug log write failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private static func debugLogURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport
            .appendingPathComponent("NativeSmartScribe", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("hud-audio.log")
    }

    private static func wavData(for tone: Tone) -> Data {
        let sampleRate = 44_100
        let channelCount = 1
        let bitsPerSample = 16
        let sampleCount = Int(Double(sampleRate) * tone.duration)
        let byteRate = sampleRate * channelCount * bitsPerSample / 8
        let blockAlign = channelCount * bitsPerSample / 8
        var data = Data()

        data.appendASCII("RIFF")
        data.appendUInt32LE(UInt32(36 + sampleCount * blockAlign))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendUInt32LE(16)
        data.appendUInt16LE(1)
        data.appendUInt16LE(UInt16(channelCount))
        data.appendUInt32LE(UInt32(sampleRate))
        data.appendUInt32LE(UInt32(byteRate))
        data.appendUInt16LE(UInt16(blockAlign))
        data.appendUInt16LE(UInt16(bitsPerSample))
        data.appendASCII("data")
        data.appendUInt32LE(UInt32(sampleCount * blockAlign))

        for sampleIndex in 0..<sampleCount {
            let t = Double(sampleIndex) / Double(sampleRate)
            let attack = min(1, t / 0.018)
            let release = min(1, (tone.duration - t) / 0.09)
            let envelope = max(0, min(attack, release))
            let mixed = tone.frequencies.reduce(0) { partial, frequency in
                partial + sin(2 * .pi * frequency * t)
            } / Double(tone.frequencies.count)
            let scaled = max(-32_767, min(32_767, mixed * envelope * 29_000))
            let sample = Int16(scaled)
            data.appendInt16LE(sample)
        }

        return data
    }
}

private struct Tone {
    let frequencies: [Double]
    let duration: Double
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt16>.size))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt32>.size))
    }

    mutating func appendInt16LE(_ value: Int16) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<Int16>.size))
    }
}
