import Foundation

public struct UsageTokenCount: Codable, Equatable, Sendable {
    public var promptTokens: Int
    public var completionTokens: Int

    public init(promptTokens: Int = 0, completionTokens: Int = 0) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }

    public var totalTokens: Int {
        promptTokens + completionTokens
    }

    public mutating func add(promptTokens: Int, completionTokens: Int) {
        self.promptTokens += max(0, promptTokens)
        self.completionTokens += max(0, completionTokens)
    }
}

public struct UsageStatisticsSettings: Codable, Equatable, Sendable {
    public var lastTransaction: UsageTokenCount
    public var totals: [String: UsageTokenCount]
    public var modelNames: [String: String]

    public init(
        lastTransaction: UsageTokenCount = UsageTokenCount(),
        totals: [String: UsageTokenCount] = [:],
        modelNames: [String: String] = [:]
    ) {
        self.lastTransaction = lastTransaction
        self.totals = totals
        self.modelNames = modelNames
    }

    public mutating func record(
        modelID: String,
        modelName: String,
        promptTokens: Int,
        completionTokens: Int
    ) {
        let transaction = UsageTokenCount(
            promptTokens: max(0, promptTokens),
            completionTokens: max(0, completionTokens)
        )
        lastTransaction = transaction
        modelNames[modelID] = modelName
        totals[modelID, default: UsageTokenCount()].add(
            promptTokens: transaction.promptTokens,
            completionTokens: transaction.completionTokens
        )
    }

    public mutating func reset(modelID: String) {
        totals[modelID] = UsageTokenCount()
    }

    public mutating func reset(modelIDs: [String]) {
        for id in modelIDs {
            totals[id] = UsageTokenCount()
        }
    }
}
