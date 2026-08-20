import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Batch media naming")
struct BatchMediaNamingTests {
    @Test("accepts every supported date token", arguments: [
        ("2023-01-16", MediaDateToken.Precision.day),
        ("2023-01", .month),
        ("2023", .year),
        ("YYYY-MM-DD", .literalPlaceholder)
    ])
    func supportedDates(date: String, precision: MediaDateToken.Precision) throws {
        let result = MediaNamingConvention.parse("\(date)_KKS_Topic_London_gb.mp3")
        let name = try #require(result.name)
        #expect(result.isAccepted)
        #expect(name.date == MediaDateToken(rawValue: date, precision: precision))
    }

    @Test("parses WHAT from fixed outer fields and preserves its underscore")
    func internalWhatUnderscore() throws {
        let filename = "2020_KKS_SB-8-1-30_Balancing-our-lives_London_gb.mp3"
        let result = MediaNamingConvention.parse(filename)
        let name = try #require(result.name)
        #expect(name.what == "SB-8-1-30_Balancing-our-lives")
        #expect(name.fileName == filename)
    }

    @Test("accepts a hyphenated WHERE")
    func hyphenatedWhere() throws {
        let name = try #require(MediaNamingConvention.parse("2023_KKS_Topic_New-York_us.wav").name)
        #expect(name.whereToken == "New-York")
    }

    @Test("rejects an uppercase extension with a typed violation")
    func uppercaseExtension() {
        let result = MediaNamingConvention.parse("2023_KKS_Topic_London_gb.MP3")
        #expect(result.name == nil)
        #expect(result.violations.contains(.uppercaseExtension))
    }

    @Test("rejects spaces")
    func spaces() {
        let result = MediaNamingConvention.parse("2023_KKS_My Topic_London_gb.mp3")
        #expect(result.name == nil)
        #expect(result.violations.contains(.spaceNotAllowed))
    }

    @Test("rejects an extra dot in the stem")
    func extraDot() {
        let result = MediaNamingConvention.parse("2023_KKS_Topic.Part_London_gb.mp3")
        #expect(result.name == nil)
        #expect(result.violations.contains(.dotInStem))
    }

    @Test("rejects forbidden component characters")
    func forbiddenCharacters() {
        let result = MediaNamingConvention.parse("2023_KKS_Topic@Home_London_gb.mp3")
        #expect(result.name == nil)
        #expect(result.violations.contains(.invalidWhat))
    }

    @Test("calendar-validates dates")
    func invalidDate() {
        let result = MediaNamingConvention.parse("2023-02-29_KKS_Topic_London_gb.mp3")
        #expect(result.name == nil)
        #expect(result.violations.contains(.invalidDate))
    }

    @Test("accepts leap dates and rejects century non-leap dates")
    func leapDates() throws {
        let leap = try #require(MediaNamingConvention.parse("2024-02-29_KKS_Topic_London_gb.mp3").name)
        #expect(leap.date == MediaDateToken(rawValue: "2024-02-29", precision: .day))
        #expect(leap.fileName == "2024-02-29_KKS_Topic_London_gb.mp3")

        for bad in ["1900-02-29", "2100-02-29"] {
            let result = MediaNamingConvention.parse("\(bad)_KKS_Topic_London_gb.mp3")
            #expect(result.name == nil)
            #expect(result.violations.contains(.invalidDate))
        }
    }

    @Test("rejects unpadded month and day components")
    func unpaddedDateComponents() {
        for bad in ["2023-1-5", "2023-01-5", "2023-1-15"] {
            let result = MediaNamingConvention.parse("\(bad)_KKS_Topic_London_gb.mp3")
            #expect(result.name == nil)
            #expect(result.violations.contains(.invalidDate))
        }
    }

    @Test("rejects empty components and an empty extension")
    func emptyComponents() {
        let emptyWho = MediaNamingConvention.parse("2023__Topic_London_gb.mp3")
        #expect(emptyWho.name == nil)
        #expect(emptyWho.violations.contains(.invalidWho))

        let emptyExtension = MediaNamingConvention.parse("2023_KKS_Topic_London_gb.")
        #expect(emptyExtension.name == nil)
        #expect(emptyExtension.violations.contains(.missingExtension))
    }

    @Test("rejects an uppercase country with a typed violation")
    func uppercaseCountry() {
        let result = MediaNamingConvention.parse("2023_KKS_Topic_London_GB.mp3")
        #expect(result.name == nil)
        #expect(result.violations.contains(.invalidCountry))
    }

    @Test("accepts 128 characters and rejects 129")
    func lengthBoundary() {
        let fixed = "2023_KKS__London_gb.mp3"
        let accepted = "2023_KKS_\(String(repeating: "A", count: 128 - fixed.count))_London_gb.mp3"
        let rejected = accepted + "A"

        #expect(accepted.count == 128)
        #expect(MediaNamingConvention.parse(accepted).isAccepted)
        #expect(rejected.count == 129)
        #expect(MediaNamingConvention.parse(rejected).violations.contains(
            .filenameTooLong(actual: 129, maximum: 128)
        ))
    }

    @Test("warns above the recommended 25-character length")
    func longNameWarning() {
        let filename = "2023_KKS_Long-Topic_London_gb.mp3"
        let result = MediaNamingConvention.parse(filename)
        #expect(result.isAccepted)
        #expect(result.warnings.contains(
            .longFilename(actual: filename.count, recommendedMaximum: 25)
        ))
    }

    @Test("legacy WHO-WHAT is rejected by default and accepted only in compatibility mode")
    func legacyCompatibility() throws {
        let filename = "2023_KKS-CC-Raghunatha-das-goswami_Amsterdam_nl.mp3"
        let strict = MediaNamingConvention.parse(filename)
        #expect(strict.name == nil)
        #expect(strict.violations.contains(.ambiguousLegacyName))

        let compatible = MediaNamingConvention.parse(filename, mode: .safeNormalize)
        let name = try #require(compatible.name)
        #expect(name.who == "KKS")
        #expect(name.what == "CC-Raghunatha-das-goswami")
        #expect(name.fileName == "2023_KKS_CC-Raghunatha-das-goswami_Amsterdam_nl.mp3")
        #expect(compatible.warnings.contains(.legacyWhoWhatSeparator))
    }

    @Test("legacy companion keeps the source stem")
    func legacyCompanionURL() throws {
        let filename = "2023-01-16_KKS-CC-Raghunatha-das-goswami_Amsterdam_nl.wav"
        let source = URL(fileURLWithPath: "/Archive/\(filename)")
        let name = try #require(MediaNamingConvention.parse(filename, mode: .safeNormalize).name)

        #expect(name.companionURL(for: source).lastPathComponent == "2023-01-16_KKS-CC-Raghunatha-das-goswami_Amsterdam_nl.txt")
    }

    @Test("legacy compatibility never fills missing semantic fields")
    func legacyMissingFields() {
        let result = MediaNamingConvention.parse("2023_KKS-Topic_nl.mp3", mode: .safeNormalize)
        #expect(result.name == nil)
        #expect(result.violations.contains(.invalidStructure))
    }

    @Test("canonical parse and render round-trip byte-for-byte")
    func roundTrip() throws {
        let filename = "2013-11-14_KKS_SB-9-20-20-27_Vrindavan_in.mp4"
        let name = try #require(MediaNamingConvention.parse(filename).name)
        #expect(name.fileName == filename)
        #expect(name.rendered() == filename)
    }

    @Test("detects output collisions case-insensitively")
    func collision() throws {
        let first = try #require(MediaNamingConvention.parse("2023_KKS_Topic_London_gb.mp3").name)
        let second = try #require(MediaNamingConvention.parse("2023_kks_Topic_London_gb.wav").name)
        let distinct = try #require(MediaNamingConvention.parse("2023_KKS_Other_London_gb.wav").name)

        let collisions = MediaNamingConvention.collisions(among: [first, second, distinct])
        #expect(collisions.count == 1)
        #expect(collisions[0].normalizedOutputName == "2023_kks_topic_london_gb.txt")
        #expect(collisions[0].sourceNames == [first.fileName, second.fileName])
    }

    @Test("companion URL changes only the extension")
    func companionURL() throws {
        let filename = "2023-01-16_KKS_CC-Raghunatha-das-goswami_Amsterdam_nl.mp3"
        let source = URL(fileURLWithPath: "/Archive/\(filename)")
        let name = try #require(MediaNamingConvention.parse(filename).name)
        let companion = name.companionURL(for: source)

        #expect(companion.lastPathComponent == "2023-01-16_KKS_CC-Raghunatha-das-goswami_Amsterdam_nl.txt")
        #expect(companion.deletingPathExtension().lastPathComponent == source.deletingPathExtension().lastPathComponent)
    }
}
