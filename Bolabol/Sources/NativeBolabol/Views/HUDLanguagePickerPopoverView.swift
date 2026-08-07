import SwiftUI
import NativeBolabolCore

@MainActor
struct HUDLanguagePickerPopoverView: View {
    let options: [HUDLanguageMenuOption]
    let languages: UserSpeechLanguages
    let onSelectLanguage: (String) -> Void
    var onClose: (() -> Void)? = nil

    @State private var searchText = ""
    @State private var hoverExitTimer: Timer?
    @State private var highlightedIndex: Int = 0
    @State private var eventMonitor: Any? = nil

    init(
        options: [HUDLanguageMenuOption],
        languages: UserSpeechLanguages,
        onSelectLanguage: @escaping (String) -> Void,
        onClose: (() -> Void)? = nil
    ) {
        self.options = options
        self.languages = languages
        self.onSelectLanguage = onSelectLanguage
        self.onClose = onClose
    }

    init(
        languages: UserSpeechLanguages,
        currentCode: String,
        supportedCodes: [String],
        onSelectLanguage: @escaping (String) -> Void,
        onClose: (() -> Void)? = nil
    ) {
        let options = HUDLanguageMenuPolicy.options(
            backend: nil,
            languages: languages,
            supportedSourceCodes: supportedCodes,
            currentCode: currentCode,
            isAutomatic: false,
            uiLanguage: .russian,
            systemLocale: .current
        )
        self.init(options: options, languages: languages, onSelectLanguage: onSelectLanguage, onClose: onClose)
    }

    private var filteredOptions: [HUDLanguageMenuOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return options }

        func score(for option: HUDLanguageMenuOption) -> Int? {
            let code = option.code.lowercased()
            let displayName = option.displayName.lowercased()
            let englishName = (LanguagePickerOrder.englishNamesByCode[code] ?? "").lowercased()

            if code == query { return 100 }
            if code.hasPrefix(query) { return 90 }
            if displayName.hasPrefix(query) { return 80 }
            if englishName.hasPrefix(query) { return 70 }
            if displayName.contains(query) { return 50 }
            if englishName.contains(query) { return 10 }
            return nil
        }

        let scored = options.compactMap { opt -> (HUDLanguageMenuOption, Int)? in
            guard let s = score(for: opt) else { return nil }
            return (opt, s)
        }

        return scored.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return a.0.displayName < b.0.displayName
        }.map(\.0)
    }

    var body: some View {
        VStack(spacing: 6) {
            // Search Bar
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Поиск / Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.08))
            .cornerRadius(6)

            Divider()

            // Language List
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(filteredOptions.enumerated()), id: \.element.code) { index, option in
                            languageRow(option, isHighlighted: index == highlightedIndex)
                                .id(option.code)
                        }
                    }
                }
                .frame(maxHeight: 240)
                .onAppear {
                    if let currentIndex = filteredOptions.firstIndex(where: { $0.isCurrent }) {
                        highlightedIndex = currentIndex
                        proxy.scrollTo(filteredOptions[currentIndex].code, anchor: .center)
                    } else if !filteredOptions.isEmpty {
                        highlightedIndex = 0
                    }
                }
                .onChange(of: highlightedIndex) { _, newIndex in
                    if filteredOptions.indices.contains(newIndex) {
                        proxy.scrollTo(filteredOptions[newIndex].code, anchor: .center)
                    }
                }
            }
        }
        .padding(8)
        .frame(minWidth: 180, maxWidth: 196)
        .onHover { isHovered in
            if isHovered {
                cancelHoverExitTimer()
            } else {
                startHoverExitTimer()
            }
        }
        .onAppear {
            setupKeyboardMonitor()
        }
        .onDisappear {
            removeKeyboardMonitor()
            cancelHoverExitTimer()
        }
    }

    @ViewBuilder
    private func languageRow(_ option: HUDLanguageMenuOption, isHighlighted: Bool) -> some View {
        let isPrimary = option.code.lowercased() == languages.primaryLanguageCode.lowercased()
        let isAdditional = option.code.lowercased() == languages.additionalLanguageCode.lowercased() && !languages.usesSameAdditionalAsPrimary

        Button {
            cancelHoverExitTimer()
            if option.isSelectable {
                onSelectLanguage(option.code)
            }
        } label: {
            HStack(spacing: 6) {
                Text(option.displayName)
                    .font(.system(size: 12, weight: option.isCurrent ? .bold : .regular))
                    .foregroundStyle(option.isCurrent ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 2)

                if isPrimary {
                    Text("P")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.18))
                        .foregroundStyle(Color.blue)
                        .cornerRadius(3)
                } else if isAdditional {
                    Text("Add")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.18))
                        .foregroundStyle(Color.orange)
                        .cornerRadius(3)
                }

                Text(option.code.uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                if option.isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                option.isCurrent
                    ? Color.accentColor.opacity(0.16)
                    : (isHighlighted ? Color.primary.opacity(0.08) : Color.clear)
            )
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .disabled(!option.isSelectable)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(option.displayName), \(option.code.uppercased())")
        .accessibilityValue(option.isCurrent ? "Selected" : "")
        .accessibilityAddTraits(option.isCurrent ? [.isButton, .isSelected] : [.isButton])
    }

    private func setupKeyboardMonitor() {
        removeKeyboardMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 53: // Escape
                onClose?()
                return nil
            case 125: // Down Arrow
                if !filteredOptions.isEmpty {
                    highlightedIndex = min(highlightedIndex + 1, filteredOptions.count - 1)
                }
                return nil
            case 126: // Up Arrow
                if !filteredOptions.isEmpty {
                    highlightedIndex = max(highlightedIndex - 1, 0)
                }
                return nil
            case 36: // Return
                if filteredOptions.indices.contains(highlightedIndex) {
                    let selected = filteredOptions[highlightedIndex]
                    if selected.isSelectable {
                        onSelectLanguage(selected.code)
                    }
                }
                return nil
            case 49: // Space
                if searchText.isEmpty && filteredOptions.indices.contains(highlightedIndex) {
                    let selected = filteredOptions[highlightedIndex]
                    if selected.isSelectable {
                        onSelectLanguage(selected.code)
                    }
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func startHoverExitTimer() {
        hoverExitTimer?.invalidate()
        hoverExitTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            Task { @MainActor in
                onClose?()
            }
        }
    }

    private func cancelHoverExitTimer() {
        hoverExitTimer?.invalidate()
        hoverExitTimer = nil
    }
}
