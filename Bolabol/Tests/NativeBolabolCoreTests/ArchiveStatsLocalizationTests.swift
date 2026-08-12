import Foundation
import NativeBolabolCore
import Testing

/// Guards against the Turkish (and ja/ko/hi) crash where archive format
/// strings swapped `%d` / `%@` and `String(format:)` SEGV'd on the main thread
/// (`SidebarView.archiveStatsText`).

private let concreteLanguages: [UILanguagePreference] = UILanguagePreference.allCases.filter {
  $0 != .system
}

private func formatSpecs(in format: String) -> [String] {
  // Match %d, %@, %1$d, %2$@, etc.
  let pattern = #"%(\d+\$)?[@d]"#
  guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
  let range = NSRange(format.startIndex..<format.endIndex, in: format)
  return regex.matches(in: format, range: range).compactMap { match in
    guard let full = Range(match.range, in: format) else { return nil }
    return String(format[full])
  }
}

@Test
func archiveStatsLabelAcceptsCountThenSizeInEveryLanguage() {
  let count = 3
  let size = "12.5 MB"

  for language in concreteLanguages {
    let format = AppText.localized(.archiveStatsLabel, language: language)
    let specs = formatSpecs(in: format)
    #expect(
      specs.count == 2,
      "\(language.rawValue) archiveStatsLabel should have 2 format args, got \(specs): \(format)"
    )
    // Must reference integer count as arg 1 and object size as arg 2
    // (positional or sequential).
    let joined = specs.joined(separator: " ")
    #expect(
      joined.contains("d") && joined.contains("@"),
      "\(language.rawValue) label specs: \(specs)"
    )

    let rendered = String(format: format, locale: nil, count as CVarArg, size as CVarArg)
    #expect(rendered.contains("3"), "\(language.rawValue) missing count in: \(rendered)")
    #expect(rendered.contains("12.5 MB"), "\(language.rawValue) missing size in: \(rendered)")
    #expect(!rendered.contains("%"), "\(language.rawValue) unexpanded placeholder: \(rendered)")
  }
}

@Test
func archiveWarningTooltipAcceptsSizeThenCountInEveryLanguage() {
  let size = "250.0 MB"
  let count = 42

  for language in concreteLanguages {
    let format = AppText.localized(.archiveWarningTooltip, language: language)
    let specs = formatSpecs(in: format)
    #expect(
      specs.count == 2,
      "\(language.rawValue) archiveWarningTooltip should have 2 format args: \(format)"
    )

    // Call site order: (formattedSize, count) → %1$@ then %2$d
    let rendered = String(format: format, locale: nil, size as CVarArg, count as CVarArg)
    #expect(rendered.contains("250.0 MB"), "\(language.rawValue) missing size: \(rendered)")
    #expect(rendered.contains("42"), "\(language.rawValue) missing count: \(rendered)")
    #expect(!rendered.contains("%1$") && !rendered.contains("%2$"),
            "\(language.rawValue) unexpanded positional: \(rendered)")
  }
}

@Test
func turkishArchiveTooltipUsesPositionalArgsInNaturalWordOrder() {
  let format = AppText.localized(.archiveWarningTooltip, language: .turkish)
  // Natural Turkish: count then size in wording, mapped via %2$d / %1$@.
  #expect(format.contains("%2$d"))
  #expect(format.contains("%1$@"))
  let rendered = String(format: format, locale: nil, "10 MB" as CVarArg, 7 as CVarArg)
  #expect(rendered.contains("7"))
  #expect(rendered.contains("10 MB"))
  #expect(rendered.lowercased().contains("kayıt") || rendered.lowercased().contains("kayit"))
}

@Test
func archiveFormatStringsDoNotCrashForZeroAndLargeValues() {
  for language in [.english, .turkish, .japanese, .korean, .hindi] as [UILanguagePreference] {
    let label = AppText.localized(.archiveStatsLabel, language: language)
    let tip = AppText.localized(.archiveWarningTooltip, language: language)
    for (count, size) in [(0, "0 B"), (1, "1 KB"), (9999, "12.3 GB")] {
      let a = String(format: label, locale: nil, count as CVarArg, size as CVarArg)
      let b = String(format: tip, locale: nil, size as CVarArg, count as CVarArg)
      #expect(!a.isEmpty)
      #expect(!b.isEmpty)
    }
  }
}
