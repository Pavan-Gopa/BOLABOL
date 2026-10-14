import Foundation
import NativeBolabolCore
import Testing

@Test
func googleTextGenerationRetryPolicyUsesBoundedAttempts() {
    // Q5a: 15 s per request; a single attempt per key (key failover, not
    // same-key retry, is owned by CloudKeyFailover).
    let policy = CloudRequestRetryPolicy.googleTextGeneration

    #expect(policy.timeoutInterval == 15)
    #expect(policy.maxAttempts == 1)
    #expect(policy.retryDelayNanoseconds == 250_000_000)
}

@Test(
    arguments: [
        URLError.Code.timedOut,
        .networkConnectionLost,
        .cannotConnectToHost,
        .cannotFindHost,
        .dnsLookupFailed
    ]
)
func cloudRequestRetryPolicyRetriesTransientNetworkErrors(code: URLError.Code) {
    let policy = CloudRequestRetryPolicy.googleTextGeneration

    #expect(policy.shouldRetry(URLError(code)))
}

@Test
func cloudRequestRetryPolicyRetriesEmptySuccessfulResponse() {
    let policy = CloudRequestRetryPolicy.googleTextGeneration

    #expect(policy.shouldRetry(CloudRequestRetryError.emptySuccessfulResponse))
}

@Test
func cloudRequestRetryPolicyDoesNotRetryCancellationOrProviderErrors() {
    let policy = CloudRequestRetryPolicy.googleTextGeneration

    #expect(!policy.shouldRetry(URLError(.cancelled)))
    #expect(!policy.shouldRetry(TestProviderError()))
}

private struct TestProviderError: Error {}
