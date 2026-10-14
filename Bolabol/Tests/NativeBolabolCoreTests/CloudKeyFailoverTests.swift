import Foundation
import NativeBolabolCore
import Testing

@Test
func cloudKeyFailoverTimeoutGoesNext() {
    #expect(CloudKeyFailover.action(for: .timeoutOrTransport) == .nextKey)
    #expect(CloudKeyFailover.action(for: .serverError(status: 500)) == .nextKey)
    #expect(CloudKeyFailover.action(for: .serverError(status: 503)) == .nextKey)
    #expect(CloudKeyFailover.action(for: .rateLimited) == .nextKey)
    #expect(CloudKeyFailover.action(for: .unauthorized(status: 401)) == .nextKey)
    #expect(CloudKeyFailover.action(for: .unauthorized(status: 403)) == .nextKey)
    #expect(CloudKeyFailover.action(for: .emptyResponse) == .nextKey)
}

@Test
func cloudKeyFailoverClientErrorStops() {
    #expect(CloudKeyFailover.action(for: .clientError(status: 400)) == .stop)
    #expect(CloudKeyFailover.action(for: .clientError(status: 404)) == .stop)
    #expect(CloudKeyFailover.action(for: .clientError(status: 422)) == .stop)
    #expect(CloudKeyFailover.action(for: .decodeError) == .stop)
}

@Test
func cloudKeyFailoverClassifiesHTTPStatus() {
    #expect(CloudKeyFailover.classifyHTTPStatus(429) == .rateLimited)
    #expect(CloudKeyFailover.classifyHTTPStatus(401) == .unauthorized(status: 401))
    #expect(CloudKeyFailover.classifyHTTPStatus(403) == .unauthorized(status: 403))
    #expect(CloudKeyFailover.classifyHTTPStatus(500) == .serverError(status: 500))
    #expect(CloudKeyFailover.classifyHTTPStatus(503) == .serverError(status: 503))
    #expect(CloudKeyFailover.classifyHTTPStatus(400) == .clientError(status: 400))
    // Quota-flavored 400s still rotate.
    #expect(CloudKeyFailover.classifyHTTPStatus(400, message: "quota exceeded") == .rateLimited)
    #expect(
        CloudKeyFailover.classifyHTTPStatus(400, message: "RESOURCE_EXHAUSTED quota") == .rateLimited
    )
}

@Test
func cloudKeyFailoverClassifiesTimeoutAsTransport() {
    #expect(CloudKeyFailover.classify(error: URLError(.timedOut)) == .timeoutOrTransport)
    #expect(CloudKeyFailover.classify(error: URLError(.networkConnectionLost)) == .timeoutOrTransport)
    #expect(CloudKeyFailover.classify(error: URLError(.cannotFindHost)) == .timeoutOrTransport)
    #expect(CloudKeyFailover.classify(error: URLError(.dnsLookupFailed)) == .timeoutOrTransport)
    #expect(CloudKeyFailover.classify(error: CloudRequestRetryError.emptySuccessfulResponse) == .emptyResponse)
}

@Test
func cloudKeyFailoverPlanSkipsDisabledAndBlankKeys() {
    let plan = CloudKeyFailover.plan(apiKeys: [
        "k1",
        "",
        "   ",
        "\(APIProviderConfiguration.disabledPrefix)k2",
        "disabled:k3",
        "k4",
    ])
    #expect(plan.keyIndices == [0, 5])
}

@Test
func cloudKeyFailoverTimeBudgetDefaultsMatchQ5a() {
    let budget = CloudKeyFailover.TimeBudget.default
    #expect(budget.perRequestSeconds == 15)
    #expect(budget.keyChainSeconds == 40)
    #expect(budget.translationSeconds == 20)
    #expect(budget.hardCapSeconds == 60)
    #expect(!budget.expired(elapsed: 59))
    #expect(budget.expired(elapsed: 60))
}

@Test
func cloudKeyFailoverTimeoutReturnsFastValue() async throws {
    let value = try await CloudKeyFailover.withTimeout(seconds: 5) { "ok" }
    #expect(value == "ok")
}

@Test
func cloudKeyFailoverTimeoutNeverStartsWorkAfterCap() async {
    // Q5a: no new key, strict retry, or provider call starts once the chain
    // cap is spent — the operation closure must not run.
    let started = TimeoutStartedFlag()
    await #expect(throws: CloudKeyFailover.TimeoutError()) {
        try await CloudKeyFailover.withTimeout(seconds: 0) {
            await started.set()
            return "never"
        }
    }
    #expect(await started.value == false)
    await #expect(throws: CloudKeyFailover.TimeoutError()) {
        try await CloudKeyFailover.withTimeout(seconds: -1) {
            await started.set()
            return "never"
        }
    }
    #expect(await started.value == false)
}

private actor TimeoutStartedFlag {
    private(set) var value = false
    func set() { value = true }
}

@Test
func cloudKeyFailoverTimeoutCancelsSlowWork() async {
    // Q5a: in-flight work is cancelled at the cap instead of running past it.
    let startedAt = Date()
    await #expect(throws: CloudKeyFailover.TimeoutError()) {
        try await CloudKeyFailover.withTimeout(seconds: 0.1) {
            try await Task.sleep(nanoseconds: 30_000_000_000)
            return "too slow"
        }
    }
    #expect(Date().timeIntervalSince(startedAt) < 5, "slow work must be cancelled, not awaited")
}
