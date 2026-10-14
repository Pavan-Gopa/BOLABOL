import Foundation
@testable import NativeBolabol
import NativeBolabolCore
import Testing

@Suite("S11 CloudKeyFailover runtime", .serialized)
struct S11CloudKeyFailoverRuntimeTests {
    @Test(arguments: [401, 429, 503, 400, 200, URLError.timedOut.rawValue, URLError.networkConnectionLost.rawValue])
    func cloudKeyFailoverExhaustionOrClientStop(status: Int) async throws {
        #expect(URLProtocol.registerClass(S11KeyFailureURLProtocol.self))
        defer { URLProtocol.unregisterClass(S11KeyFailureURLProtocol.self) }
        S11KeyFailureURLProtocol.reset(status: status)
        let engine = CloudTextPolishingEngine(
            kind: .openRouter,
            configuration: APIProviderConfiguration(
                apiKeys: ["s11-first", "#DISABLED#s11-disabled", "s11-second", "s11-last"],
                textModel: "s11-qa-model",
                baseURL: "https://s11-qa.invalid/v1"
            )
        )
        let request = PolishingRequest(
            rawText: "Please polish this sentence.",
            variant: .variantOne,
            template: .defaultTemplate(for: .variantOne)
        )
        do {
            _ = try await engine.polish(request)
            Issue.record("all enabled keys fail: no successful output is possible")
        } catch {
            #expect(
                CloudTextPolishingEngine.failoverFailure(for: error)
                    == (status < 0 ? .timeoutOrTransport : (status == 200 ? .emptyResponse : CloudKeyFailover.classifyHTTPStatus(status))),
                "the exhausted chain must surface its last provider failure"
            )
        }
        let requests = S11KeyFailureURLProtocol.requests
        let expectedKeys = status == 400
            ? ["Bearer s11-first"]
            : ["Bearer s11-first", "Bearer s11-second", "Bearer s11-last"]
        #expect(requests.map { $0.value(forHTTPHeaderField: "Authorization") ?? "" } == expectedKeys)
        #expect(requests.allSatisfy { $0.timeoutInterval == 15 })
    }

    @Test
    func cloudKeyFailoverKeyChainBudgetCannotAcceptLateInFlightReply() async throws {
        #expect(URLProtocol.registerClass(S11KeyFailureURLProtocol.self))
        defer { URLProtocol.unregisterClass(S11KeyFailureURLProtocol.self) }
        S11KeyFailureURLProtocol.reset(status: 200, delay: 1)
        let engine = CloudTextPolishingEngine(
            kind: .openRouter,
            configuration: APIProviderConfiguration(
                apiKeys: ["s11-first", "s11-second"],
                textModel: "s11-qa-model",
                baseURL: "https://s11-qa.invalid/v1"
            )
        )
        let request = PolishingRequest(
            rawText: "Please polish this sentence.",
            variant: .variantOne,
            template: .defaultTemplate(for: .variantOne)
        )
        // The injected 50 ms chain budget is spent long before the 1 s
        // response. Per-request 15 s is not permission to overrun that cap.
        do {
            let result = try await engine.polish(request, keyChainSeconds: 0.05)
            Issue.record("accepted late reply after the key-chain budget: \(result.text)")
        } catch {
            #expect(S11KeyFailureURLProtocol.requests.count == 1)
        }
    }
}

// Restrict interception to the reserved test host. No production request or
// credential can enter this fixture, and no external service is contacted.
private final class S11KeyFailureURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var captured: [URLRequest] = []
    nonisolated(unsafe) private static var responseStatus = 503
    nonisolated(unsafe) private static var responseDelay: TimeInterval = 0

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    static func reset(status: Int, delay: TimeInterval = 0) {
        lock.lock()
        defer { lock.unlock() }
        captured.removeAll()
        responseStatus = status
        responseDelay = delay
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "s11-qa.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.captured.append(request)
        let status = Self.responseStatus
        let delay = Self.responseDelay
        Self.lock.unlock()
        if status < 0 {
            client?.urlProtocol(self, didFailWithError: URLError(URLError.Code(rawValue: status)))
            return
        }
        let body = status == 200
            ? "{\"choices\":[{\"message\":{\"content\":\"\(delay > 0 ? "This is the English result." : "")\"}}]}"
            : "{\"error\":{\"message\":\"S11 fixture failure\"}}"
        if delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
                deliver(status: status, body: body)
            }
        } else {
            deliver(status: status, body: body)
        }
    }

    private func deliver(status: Int, body: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
