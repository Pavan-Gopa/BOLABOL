import Darwin
import Foundation
import Testing
import VaniScriptCore
@testable import VaniScript

@Suite("Atomic companion writer")
struct AtomicCompanionWriterTests {
    @Test("creates absent exact output and returns its hash")
    func absentOutput() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let request = try fixture.request()
        let result = try AtomicCompanionWriter().write(Data("new text".utf8), request: request)

        #expect(result.disposition == .created)
        #expect(result.outputURL == fixture.output)
        #expect(result.outputFingerprint.sha256 == "cb0208b0b1fa06bc59f85c8b2be1e45ff2ef6ddbf0cef02e9f276b8208ea48ab")
        #expect(try String(contentsOf: fixture.output, encoding: .utf8) == "new text")
        #expect(fixture.ownedTemporaryFiles.isEmpty)
    }

    @Test("replaces output only when its known generated hash is unchanged")
    func generatedReplacement() throws {
        let fixture = try Fixture(output: "generated")
        defer { fixture.remove() }
        let known = GeneratedOutputFingerprint(sha256: try fixture.outputHash())
        let request = try fixture.request(knownGeneratedOutput: known)

        let result = try AtomicCompanionWriter().write(Data("replacement".utf8), request: request)

        #expect(result.disposition == .replacedGenerated)
        #expect(try String(contentsOf: fixture.output, encoding: .utf8) == "replacement")
    }

    @Test("preserves unknown existing output")
    func unknownOutput() throws {
        let fixture = try Fixture(output: "user work")
        defer { fixture.remove() }

        #expect(throws: AtomicCompanionWriterError.existingOutputNotKnownGenerated) {
            try AtomicCompanionWriter().write(Data("replacement".utf8), request: try fixture.request())
        }
        #expect(try String(contentsOf: fixture.output, encoding: .utf8) == "user work")
    }

    @Test("refuses initial symlink and nonregular outputs")
    func initialNonregularOutputs() throws {
        let symlinkFixture = try Fixture()
        defer { symlinkFixture.remove() }
        let target = symlinkFixture.directory.appendingPathComponent("user-target.txt")
        try Data("target bytes".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: symlinkFixture.output, withDestinationURL: target)

        #expect(throws: AtomicCompanionWriterError.existingOutputNotKnownGenerated) {
            try AtomicCompanionWriter().write(
                Data("replacement".utf8),
                request: try symlinkFixture.request(knownGeneratedOutput: GeneratedOutputFingerprint(sha256: symlinkFixture.outputHash()))
            )
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == "target bytes")

        let directoryFixture = try Fixture()
        defer { directoryFixture.remove() }
        try FileManager.default.createDirectory(at: directoryFixture.output, withIntermediateDirectories: false)

        #expect(throws: AtomicCompanionWriterError.existingOutputNotKnownGenerated) {
            try AtomicCompanionWriter().write(
                Data("replacement".utf8),
                request: try directoryFixture.request(knownGeneratedOutput: GeneratedOutputFingerprint(sha256: String(repeating: "0", count: 64)))
            )
        }
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: directoryFixture.output.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test("preserves output modified after generation")
    func modifiedOutput() throws {
        let fixture = try Fixture(output: "user edit")
        defer { fixture.remove() }
        let stale = GeneratedOutputFingerprint(sha256: String(repeating: "0", count: 64))

        #expect(throws: AtomicCompanionWriterError.existingOutputModified) {
            try AtomicCompanionWriter().write(
                Data("replacement".utf8),
                request: try fixture.request(knownGeneratedOutput: stale)
            )
        }
        #expect(try String(contentsOf: fixture.output, encoding: .utf8) == "user edit")
    }

    @Test("output created immediately before commit is preserved")
    func outputCreatedBeforeCommit() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let writer = AtomicCompanionWriter(beforeCommit: {
            try! Data("user work".utf8).write(to: fixture.output)
        })

        #expect(throws: AtomicCompanionWriterError.existingOutputNotKnownGenerated) {
            try writer.write(Data("generated".utf8), request: try fixture.request())
        }
        #expect(try String(contentsOf: fixture.output, encoding: .utf8) == "user work")
        #expect(fixture.ownedTemporaryFiles.isEmpty)
    }

    @Test("output edited immediately before replacement is preserved")
    func outputEditedBeforeCommit() throws {
        let fixture = try Fixture(output: "generated")
        defer { fixture.remove() }
        let known = GeneratedOutputFingerprint(sha256: try fixture.outputHash())
        let writer = AtomicCompanionWriter(beforeCommit: {
            try! Data("user edit".utf8).write(to: fixture.output)
        })

        #expect(throws: AtomicCompanionWriterError.existingOutputModified) {
            try writer.write(
                Data("replacement".utf8),
                request: try fixture.request(knownGeneratedOutput: known)
            )
        }
        #expect(try String(contentsOf: fixture.output, encoding: .utf8) == "user edit")
        #expect(fixture.ownedTemporaryFiles.isEmpty)
    }

    @Test("symlink substituted immediately before replacement is preserved without touching target")
    func outputSymlinkedBeforeCommit() throws {
        let fixture = try Fixture(output: "generated")
        defer { fixture.remove() }
        let known = GeneratedOutputFingerprint(sha256: try fixture.outputHash())
        let target = fixture.directory.appendingPathComponent("user-target.txt")
        try Data("target bytes".utf8).write(to: target)
        let writer = AtomicCompanionWriter(beforeCommit: {
            try! FileManager.default.removeItem(at: fixture.output)
            try! FileManager.default.createSymbolicLink(at: fixture.output, withDestinationURL: target)
        })

        #expect(throws: AtomicCompanionWriterError.existingOutputModified) {
            try writer.write(
                Data("replacement".utf8),
                request: try fixture.request(knownGeneratedOutput: known)
            )
        }
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: fixture.output.path)
        #expect(destination == target.path)
        #expect(try String(contentsOf: target, encoding: .utf8) == "target bytes")
        #expect(fixture.ownedTemporaryFiles.isEmpty)
    }

    @Test("source fingerprint change immediately before commit preserves output")
    func sourceChange() throws {
        let fixture = try Fixture(output: "generated")
        defer { fixture.remove() }
        let known = GeneratedOutputFingerprint(sha256: try fixture.outputHash())
        let writer = AtomicCompanionWriter(beforeCommit: {
            try! Data("changed source".utf8).write(to: fixture.source)
        })

        #expect(throws: AtomicCompanionWriterError.sourceChanged) {
            try writer.write(
                Data("replacement".utf8),
                request: try fixture.request(knownGeneratedOutput: known)
            )
        }
        #expect(try String(contentsOf: fixture.output, encoding: .utf8) == "generated")
        #expect(fixture.ownedTemporaryFiles.isEmpty)
    }

    @Test("case-insensitive sibling collision blocks before writing")
    func collision() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let collision = fixture.directory.appendingPathComponent(fixture.output.lastPathComponent.uppercased())
        try Data("collision".utf8).write(to: collision)

        #expect(throws: AtomicCompanionWriterError.caseInsensitiveCollision(existingName: collision.lastPathComponent)) {
            try AtomicCompanionWriter().write(Data("text".utf8), request: try fixture.request())
        }
        #expect(try String(contentsOf: collision, encoding: .utf8) == "collision")
    }

    @Test("permission failure is typed and preserves output")
    func permissionFailure() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let writer = AtomicCompanionWriter(createTemporary: { _ in
            Darwin.errno = EACCES
            return -1
        })

        #expect(throws: AtomicCompanionWriterError.permissionDenied) {
            try writer.write(Data("text".utf8), request: try fixture.request())
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.output.path))
    }

    @Test("fsync failure is typed and final output is never partially visible")
    func syncFailure() throws {
        let fixture = try Fixture(output: "complete old output")
        defer { fixture.remove() }
        let known = GeneratedOutputFingerprint(sha256: try fixture.outputHash())
        let writer = AtomicCompanionWriter(synchronize: { _ in
            Darwin.errno = EIO
            return -1
        })

        #expect(throws: AtomicCompanionWriterError.syncFailed(code: EIO)) {
            try writer.write(Data(repeating: 65, count: 1_000_000), request: try fixture.request(knownGeneratedOutput: known))
        }
        #expect(try String(contentsOf: fixture.output, encoding: .utf8) == "complete old output")
        #expect(fixture.ownedTemporaryFiles.isEmpty)
    }

    @Test("cleanup removes only stale owned temporary files")
    func staleTemporaryCleanup() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let stale = fixture.directory.appendingPathComponent(
            AtomicCompanionWriter.temporaryPrefix + fixture.output.lastPathComponent + ".stale"
        )
        let unrelated = fixture.directory.appendingPathComponent(".other.partial")
        let otherOutputTemp = fixture.directory.appendingPathComponent(
            AtomicCompanionWriter.temporaryPrefix + "other.txt.stale"
        )
        try Data().write(to: stale)
        try Data().write(to: unrelated)
        try Data().write(to: otherOutputTemp)

        _ = try AtomicCompanionWriter().write(Data("text".utf8), request: fixture.request())

        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        #expect(FileManager.default.fileExists(atPath: otherOutputTemp.path))
    }
}

private final class Fixture: @unchecked Sendable {
    let directory: URL
    let source: URL
    let output: URL

    init(output initialOutput: String? = nil) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AtomicCompanionWriterTests-\(UUID().uuidString)", isDirectory: true)
        source = directory.appendingPathComponent("2023_KKS_Topic_London_gb.mp3")
        output = directory.appendingPathComponent("2023_KKS_Topic_London_gb.txt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("source media".utf8).write(to: source)
        if let initialOutput { try Data(initialOutput.utf8).write(to: output) }
    }

    func request(knownGeneratedOutput: GeneratedOutputFingerprint? = nil) throws -> CompanionWriteRequest {
        CompanionWriteRequest(
            sourceURL: source,
            outputURL: output,
            expectedSourceFingerprint: try AtomicCompanionWriter.fingerprint(sourceURL: source),
            knownGeneratedOutput: knownGeneratedOutput
        )
    }

    func outputHash() throws -> String {
        let fingerprint = try AtomicCompanionWriter.fingerprint(sourceURL: output)
        return fingerprint.sha256
    }

    var ownedTemporaryFiles: [URL] {
        let prefix = AtomicCompanionWriter.temporaryPrefix + output.lastPathComponent + "."
        return (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix(prefix) } ?? []
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
