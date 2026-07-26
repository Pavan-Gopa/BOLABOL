import Testing
import Foundation
@testable import VaniScriptCore

// A4 (API_USAGE §9.1): unit tests for CloudKeyValidator. Covers the pure HTTP-status →
// validation-status mapping and the async `validate` path with a mocked fetcher, so no
// real network call is made (invariant §14: offline, deterministic, no keys in source).
@Suite("CloudKeyValidator (A4)")
struct CloudKeyValidatorTests {

    // MARK: - Status mapping (pure)

    @Test("2xx maps to valid")
    func mapsSuccess() {
        #expect(CloudKeyValidator.status(forHTTPStatus: 200) == .valid)
        #expect(CloudKeyValidator.status(forHTTPStatus: 204) == .valid)
    }

    @Test("401/403 map to invalid (bad key)")
    func mapsUnauthorized() {
        if case .invalid = CloudKeyValidator.status(forHTTPStatus: 401) {} else { Issue.record("401 should be invalid") }
        if case .invalid = CloudKeyValidator.status(forHTTPStatus: 403) {} else { Issue.record("403 should be invalid") }
    }

    @Test("429 (rate limited) is treated as a valid key")
    func mapsRateLimited() {
        #expect(CloudKeyValidator.status(forHTTPStatus: 429) == .valid)
    }

    @Test("other non-2xx maps to invalid with the code")
    func mapsGenericFailure() {
        if case let .invalid(reason) = CloudKeyValidator.status(forHTTPStatus: 500) {
            #expect(reason.contains("500"))
        } else {
            Issue.record("500 should be invalid")
        }
    }

    // MARK: - Async validate with mocked fetcher

    @Test("empty key returns idle without hitting the network")
    func emptyKeyIdle() async throws {
        let descriptor = try #require(CloudProviderCatalog.descriptor(for: CloudProviderCatalog.openaiID))
        let validator = CloudKeyValidator(fetcher: { _ in
            Issue.record("fetcher must not be called for an empty key")
            return (Data(), HTTPURLResponse())
        })
        let status = await validator.validate(descriptor: descriptor, apiKey: "   ")
        #expect(status == .idle)
    }

    @Test("valid key (200) resolves to valid")
    func validKey() async throws {
        let descriptor = try #require(CloudProviderCatalog.descriptor(for: CloudProviderCatalog.geminiID))
        let validator = CloudKeyValidator(fetcher: { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("{}".utf8), response)
        })
        let status = await validator.validate(descriptor: descriptor, apiKey: "GOOD")
        #expect(status == .valid)
    }

    @Test("bad key (401) resolves to invalid")
    func badKey() async throws {
        let descriptor = try #require(CloudProviderCatalog.descriptor(for: CloudProviderCatalog.openaiID))
        let validator = CloudKeyValidator(fetcher: { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })
        let status = await validator.validate(descriptor: descriptor, apiKey: "BAD")
        if case .invalid = status {} else { Issue.record("401 should resolve to invalid") }
    }

    @Test("network error resolves to invalid (red badge), never throws")
    func networkErrorInvalid() async throws {
        let descriptor = try #require(CloudProviderCatalog.descriptor(for: CloudProviderCatalog.openaiID))
        let validator = CloudKeyValidator(fetcher: { _ in
            throw URLError(.notConnectedToInternet)
        })
        let status = await validator.validate(descriptor: descriptor, apiKey: "KEY")
        if case .invalid = status {} else { Issue.record("network error should resolve to invalid") }
    }

    @Test("providers without a listable endpoint treat a present key as valid")
    func customProviderValid() async throws {
        let descriptor = try #require(CloudProviderCatalog.descriptor(for: CloudProviderCatalog.customID))
        let validator = CloudKeyValidator(fetcher: { _ in
            Issue.record("custom provider must not perform a request")
            return (Data(), HTTPURLResponse())
        })
        let status = await validator.validate(descriptor: descriptor, apiKey: "KEY")
        #expect(status == .valid)
    }
}
