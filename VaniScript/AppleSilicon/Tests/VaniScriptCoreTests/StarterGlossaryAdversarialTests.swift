import Foundation
import Testing
@testable import VaniScriptCore

@Suite("Starter glossary integrity and merge boundaries")
struct StarterGlossaryAdversarialTests {
    @Test("starter glossary IDs and normalized sources are unique")
    func identitiesAreUnique() {
        let entries = StarterGlossary.entries
        #expect(!entries.isEmpty)
        #expect(Set(entries.map(\.id)).count == entries.count)
        let normalizedSources = entries.map { $0.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        #expect(Set(normalizedSources).count == entries.count)
    }

    @Test("starter entries have complete Russian/default translations and remember flag")
    func translationsAreComplete() {
        for entry in StarterGlossary.entries {
            #expect(!entry.id.isEmpty)
            #expect(!entry.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!entry.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(entry.translations["Russian"] == entry.translation)
            #expect(entry.translations["Default"] == entry.translation)
            #expect(entry.remember)
        }
    }

    @Test("generated starter IDs are stable ASCII-like slugs with no spaces")
    func idsAreSlugged() {
        for entry in StarterGlossary.entries {
            #expect(entry.id.hasPrefix("starter-vaishnava-"))
            #expect(!entry.id.contains(" "))
            #expect(entry.id == entry.id.lowercased())
            #expect(entry.id.unicodeScalars.allSatisfy { $0.isASCII })
        }
    }

    @Test("variants never contain blank strings or exact canonical source")
    func variantsAreUseful() {
        for entry in StarterGlossary.entries {
            #expect(entry.variants.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            #expect(!entry.variants.contains(entry.source))
            #expect(Set(entry.variants).count == entry.variants.count)
        }
    }

    @Test("merging into empty settings installs exactly the starter glossary")
    func mergeIntoEmpty() {
        #expect(StarterGlossary.mergeStarterGlossary([]) == StarterGlossary.entries)
    }

    @Test("merge is idempotent")
    func mergeIsIdempotent() {
        let once = StarterGlossary.mergeStarterGlossary([])
        let twice = StarterGlossary.mergeStarterGlossary(once)
        #expect(twice == once)
    }

    @Test("existing ID suppresses its starter entry without replacing caller data")
    func existingIDWins() {
        var custom = StarterGlossary.entries[0]
        custom.translation = "CUSTOM TRANSLATION"
        custom.translations["Russian"] = "CUSTOM TRANSLATION"

        let merged = StarterGlossary.mergeStarterGlossary([custom])
        #expect(merged.first == custom)
        #expect(merged.filter { $0.id == custom.id }.count == 1)
        #expect(merged.count == StarterGlossary.entries.count)
    }

    @Test("existing source suppresses starter entry case-insensitively even under a different ID")
    func existingSourceWinsCaseInsensitively() {
        let starter = StarterGlossary.entries[0]
        var custom = starter
        custom.id = "custom-user-entry"
        custom.source = "  \(starter.source.uppercased())  "
        custom.translation = "USER VALUE"

        let merged = StarterGlossary.mergeStarterGlossary([custom])
        #expect(merged.first == custom)
        #expect(!merged.contains { $0.id == starter.id })
        #expect(merged.count == StarterGlossary.entries.count)
    }
}
