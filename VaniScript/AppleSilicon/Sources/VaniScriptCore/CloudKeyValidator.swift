import Foundation

// MARK: - CloudKeyValidator
//
// Role: VaniScriptCore service (A4) that performs a lightweight "is this API key
// accepted?" check for a cloud provider, so the provider card can show a
// Checking / Valid / Invalid badge. It reuses the same per-provider endpoints and
// auth as CloudModelCatalog (a successful models-list request == a valid key, §9.1),
// which keeps the two features consistent and avoids a second set of URLs.
//
// It must NOT: transcribe/translate, persist anything, or log/embed API keys. The
// network boundary is injected (`CloudHTTPFetcher`) so unit tests exercise the
// status mapping with mocked responses — no real requests.
//
// Debounce note: validation is *triggered* by the UI on focus-loss / typing pause
// (§9.1). This type stays stateless and cheap; the debounce lives in the view layer
// (task cancellation on key change) so the core has no timers to own or cancel.
//
// Invariants (§14): no keys/tokens in source or logs; migration-safe; buildable.

/// Result of a key validation attempt. `invalid` carries a short, human-readable
/// reason for the red badge tooltip (never the key or raw response body).
public enum CloudKeyValidationStatus: Equatable, Sendable {
    /// No key entered yet (or key cleared) — nothing to show.
    case idle
    /// Request in flight — grey "Checking…" badge.
    case checking
    /// Provider accepted the key — green "● Valid" badge.
    case valid
    /// Provider rejected the key or the check failed — red "● Invalid" badge.
    case invalid(reason: String)
}

public struct CloudKeyValidator: Sendable {
    private let fetcher: CloudHTTPFetcher

    public init(fetcher: @escaping CloudHTTPFetcher = CloudHTTP.live) {
        self.fetcher = fetcher
    }

    /// Validate `apiKey` for the given provider. Returns `.idle` for an empty key,
    /// `.valid` on a 2xx response, otherwise `.invalid` with a mapped reason. Network
    /// errors are also mapped to `.invalid` (the UI simply shows a red badge). This
    /// call never throws — status *is* the result.
    public func validate(descriptor: CloudProviderDescriptor, apiKey: String, baseURL: String? = nil) async -> CloudKeyValidationStatus {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .idle }

        // Providers without a listable endpoint (custom / none) can't be validated
        // cheaply; treat a present key as "valid" so the UI doesn't block the user.
        guard let request = CloudModelCatalog.listRequest(descriptor: descriptor, apiKey: key, baseURL: baseURL) else {
            return .valid
        }

        do {
            let (_, response) = try await fetcher(request)
            let status = Self.status(forHTTPStatus: response.statusCode)

            if case .invalid = status, descriptor.id == CloudProviderCatalog.qwenID {
                let tokenPlanBase = "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1/models"
                if request.url?.absoluteString != tokenPlanBase, let fallbackURL = URL(string: tokenPlanBase) {
                    var fallbackReq = URLRequest(url: fallbackURL)
                    fallbackReq.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    if let (_, fbResp) = try? await fetcher(fallbackReq) {
                        let fbStatus = Self.status(forHTTPStatus: fbResp.statusCode)
                        if fbStatus == .valid {
                            return .valid
                        }
                    }
                }
            }

            return status
        } catch is CancellationError {
            // Superseded by a newer keystroke — keep "checking" so the UI's newer task wins.
            return .checking
        } catch {
            return .invalid(reason: "Could not reach provider.")
        }
    }

    /// Map an HTTP status code to a validation status (pure — unit-tested directly).
    /// 2xx = valid; 401/403 = bad key; 429 = rate-limited (key likely fine); other
    /// non-2xx = generic failure with the code.
    public static func status(forHTTPStatus code: Int) -> CloudKeyValidationStatus {
        switch code {
        case 200...299:
            return .valid
        case 401, 403:
            return .invalid(reason: "Invalid or unauthorized API key.")
        case 429:
            // Rate-limited: the key is accepted, the provider is just throttling.
            return .valid
        default:
            return .invalid(reason: "Provider returned HTTP \(code).")
        }
    }
}
