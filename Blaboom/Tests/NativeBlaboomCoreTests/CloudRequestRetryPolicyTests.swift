import Foundation
import NativeBlaboomCore
import Testing

@Test
func googleTextGenerationRetryPolicyUsesBoundedAttempts() {
    let policy = CloudRequestRetryPolicy.googleTextGeneration

    #expect(policy.timeoutInterval == 20)
    #expect(policy.maxAttempts == 2)
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
