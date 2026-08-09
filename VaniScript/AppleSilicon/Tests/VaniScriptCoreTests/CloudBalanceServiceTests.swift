import Testing
import Foundation
@testable import VaniScriptCore

// A7 (API_USAGE §11): unit tests for CloudBalanceService — the real-balance adapter.
// Network is mocked: tests feed canned JSON through the pure OpenRouter parsers and
// drive the actor with an injected fetcher, so they run offline/deterministically and
// never touch a key or the network (invariant §14). They also lock in the honesty
// rules: no real balance for `.none`/`.estimated`, quiet fallback on error, Ollama
// stays plan-based (never a fake "$").
@Suite("CloudBalanceService (A7)")
struct CloudBalanceServiceTests {

    // MARK: - OpenRouter parsers

    @Test("parses /api/v1/credits total_credits + total_usage")
    func parsesCredits() throws {
        let json = Data(#"{ "data": { "total_credits": 25.0, "total_usage": 5.5 } }"#.utf8)
        let (total, usage) = try OpenRouterBalanceProvider.parseCredits(json)
        #expect(total == 25.0)
        #expect(usage == 5.5)
    }

    @Test("parses /api/v1/key limit + limit_remaining, tolerating nulls")
    func parsesKey() throws {
        let withCap = Data(#"{ "data": { "limit": 10.0, "limit_remaining": 4.0, "usage": 6.0, "is_free_tier": false } }"#.utf8)
        let (limit, remaining) = try OpenRouterBalanceProvider.parseKey(withCap)
        #expect(limit == 10.0)
        #expect(remaining == 4.0)

        let unlimited = Data(#"{ "data": { "limit": null, "limit_remaining": null, "usage": 6.0 } }"#.utf8)
        let (limit2, remaining2) = try OpenRouterBalanceProvider.parseKey(unlimited)
        #expect(limit2 == nil)
        #expect(remaining2 == nil)
    }

    @Test("throws unparsableResponse on malformed bodies")
    func throwsOnMalformed() {
        let bad = Data("not json".utf8)
        #expect(throws: CloudBalanceError.self) { try OpenRouterBalanceProvider.parseCredits(bad) }
        #expect(throws: CloudBalanceError.self) { try OpenRouterBalanceProvider.parseKey(bad) }
    }

    // MARK: - OpenRouter balance mapping

    @Test("unlimited key → remaining = credits − usage, total = credits")
    func mapsUnlimitedKey() throws {
        let credits = Data(#"{ "data": { "total_credits": 25.0, "total_usage": 5.0 } }"#.utf8)
        let key = Data(#"{ "data": { "limit": null, "limit_remaining": null } }"#.utf8)
        let info = try OpenRouterBalanceProvider.balance(creditsData: credits, keyData: key)
        #expect(info == .usd(remaining: 20.0, total: 25.0))
    }

    @Test("per-key cap tighter than account balance wins (never over-report)")
    func mapsPerKeyCap() throws {
        // Account leaves 20 spendable, but the key is capped to 4 remaining / limit 10.
        let credits = Data(#"{ "data": { "total_credits": 25.0, "total_usage": 5.0 } }"#.utf8)
        let key = Data(#"{ "data": { "limit": 10.0, "limit_remaining": 4.0 } }"#.utf8)
        let info = try OpenRouterBalanceProvider.balance(creditsData: credits, keyData: key)
        #expect(info == .usd(remaining: 4.0, total: 10.0))
    }

    // MARK: - Ollama Cloud (plan-based, never USD)

    @Test("Ollama Cloud reports plan-based label, never a $ amount")
    func ollamaIsPlanBased() async throws {
        let info = try await OllamaCloudBalanceProvider().fetchBalance(apiKey: "IGNORED")
        #expect(info == .planLimits(label: "Plan-based (GPU time)", detail: ""))
    }

    // MARK: - Service routing + honesty rules

    @Test(".estimated / .none providers never fetch and stay unavailable")
    func estimatedProvidersNeverFetch() async throws {
        let counter = CallCounter()
        let service = CloudBalanceService(fetcher: { _ in
            await counter.increment()
            return (Data(), HTTPURLResponse(url: URL(string: "https://x")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        for id in [CloudProviderCatalog.geminiID, CloudProviderCatalog.openaiID,
                   CloudProviderCatalog.qwenID, CloudProviderCatalog.customID] {
            let descriptor = try #require(CloudProviderCatalog.descriptor(for: id))
            let info = await service.balance(for: descriptor, apiKey: "SECRET")
            #expect(info == .unavailable)
        }
        #expect(await counter.value == 0)
    }

    @Test("OpenRouter with empty key stays unavailable without fetching")
    func openRouterEmptyKey() async throws {
        let counter = CallCounter()
        let service = CloudBalanceService(fetcher: { _ in
            await counter.increment()
            return (Data(), HTTPURLResponse(url: URL(string: "https://x")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let descriptor = try #require(CloudProviderCatalog.descriptor(for: CloudProviderCatalog.openrouterID))
        let info = await service.balance(for: descriptor, apiKey: "   ")
        #expect(info == .unavailable)
        #expect(await counter.value == 0)
    }

    @Test("OpenRouter end-to-end via mocked fetcher → real USD balance, then cached")
    func openRouterEndToEndCached() async throws {
        let counter = CallCounter()
        let service = CloudBalanceService(fetcher: { request in
            await counter.increment()
            let body: String
            if request.url?.absoluteString.contains("/credits") == true {
                body = #"{ "data": { "total_credits": 30.0, "total_usage": 12.0 } }"#
            } else {
                body = #"{ "data": { "limit": null, "limit_remaining": null } }"#
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        })
        let descriptor = try #require(CloudProviderCatalog.descriptor(for: CloudProviderCatalog.openrouterID))

        let first = await service.balance(for: descriptor, apiKey: "SECRET")
        #expect(first == .usd(remaining: 18.0, total: 30.0))
        // Second call within TTL is served from cache (no extra fetches).
        let second = await service.balance(for: descriptor, apiKey: "SECRET")
        #expect(second == first)
        #expect(await counter.value == 2) // one credits + one key, only once
    }

    @Test("HTTP error → quiet fallback to unavailable (no throw, no crash)")
    func quietFallbackOnError() async throws {
        let service = CloudBalanceService(fetcher: { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        })
        let descriptor = try #require(CloudProviderCatalog.descriptor(for: CloudProviderCatalog.openrouterID))
        let info = await service.balance(for: descriptor, apiKey: "BAD")
        #expect(info == .unavailable)
    }

    @Test("force refresh bypasses the cache")
    func forceRefreshBypassesCache() async throws {
        let counter = CallCounter()
        let service = CloudBalanceService(fetcher: { request in
            await counter.increment()
            let body = request.url?.absoluteString.contains("/credits") == true
                ? #"{ "data": { "total_credits": 30.0, "total_usage": 0.0 } }"#
                : #"{ "data": { "limit": null, "limit_remaining": null } }"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        })
        let descriptor = try #require(CloudProviderCatalog.descriptor(for: CloudProviderCatalog.openrouterID))
        _ = await service.balance(for: descriptor, apiKey: "SECRET")
        _ = await service.balance(for: descriptor, apiKey: "SECRET", force: true)
        #expect(await counter.value == 4) // two fetches per call, forced past the cache
    }
}

// Small actor to count fetcher invocations from concurrency-safe test closures.
private actor CallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
