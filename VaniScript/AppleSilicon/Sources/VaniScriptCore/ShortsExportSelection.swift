import Foundation

public struct ShortsExportJob: Codable, Equatable, Hashable, Sendable {
    public var index: Int
    public var language: ShortsIdeaDisplayLanguage

    public init(index: Int, language: ShortsIdeaDisplayLanguage) {
        self.index = index
        self.language = language
    }
}

public struct ShortsExportSelection: Codable, Equatable, Sendable {
    private var selectedJobs: Set<ShortsExportJob>

    public init(_ selectedJobs: Set<ShortsExportJob> = []) {
        self.selectedJobs = selectedJobs
    }

    public func contains(index: Int, language: ShortsIdeaDisplayLanguage) -> Bool {
        selectedJobs.contains(ShortsExportJob(index: index, language: language))
    }

    public mutating func toggle(index: Int, language: ShortsIdeaDisplayLanguage) {
        let job = ShortsExportJob(index: index, language: language)
        if selectedJobs.contains(job) {
            selectedJobs.remove(job)
        } else {
            selectedJobs.insert(job)
        }
    }

    public mutating func insert(index: Int, language: ShortsIdeaDisplayLanguage) {
        selectedJobs.insert(ShortsExportJob(index: index, language: language))
    }

    public mutating func removeAll() {
        selectedJobs.removeAll()
    }

    public mutating func selectAllSource(validClipCount: Int) {
        selectedJobs = Set((0..<max(0, validClipCount)).map { ShortsExportJob(index: $0, language: .source) })
    }

    public func selectedCount(validClipCount: Int) -> Int {
        jobs(validClipCount: validClipCount).count
    }

    public func jobs(validClipCount: Int) -> [ShortsExportJob] {
        selectedJobs
            .filter { $0.index >= 0 && $0.index < validClipCount }
            .sorted {
                if $0.index != $1.index {
                    return $0.index < $1.index
                }
                return languageSortRank($0.language) < languageSortRank($1.language)
            }
    }

    public func indexes(for language: ShortsIdeaDisplayLanguage, validClipCount: Int) -> Set<Int> {
        Set(jobs(validClipCount: validClipCount).filter { $0.language == language }.map(\.index))
    }

    private func languageSortRank(_ language: ShortsIdeaDisplayLanguage) -> Int {
        switch language {
        case .source:
            return 0
        case .target:
            return 1
        }
    }
}
