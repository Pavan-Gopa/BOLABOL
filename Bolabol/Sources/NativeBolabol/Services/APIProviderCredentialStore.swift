import Foundation
import NativeBolabolCore
import Security

protocol APIProviderCredentialStoring {
  func loadKeys(for kind: APIProviderKind) -> [String]
  func saveKeys(_ keys: [String], for kind: APIProviderKind) throws
  /// Account-string variants for named custom instances (ADR-031). The
  /// migrated legacy instance keeps `api-provider.custom.keys`; new ones use
  /// `api-provider.custom.<uuid>.keys` (see `CustomAPIProviderInstance`).
  func loadKeys(account: String) -> [String]
  func saveKeys(_ keys: [String], account: String) throws
}

struct KeychainAPIProviderCredentialStore: APIProviderCredentialStoring {
  private let service: String

  init(
    service: String =
      "\(Bundle.main.bundleIdentifier ?? "NativeBolabol").api-provider-credentials"
  ) {
    self.service = service
  }

  func loadKeys(for kind: APIProviderKind) -> [String] {
    loadKeys(account: account(for: kind))
  }

  func loadKeys(account: String) -> [String] {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
    ]

    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data,
      let keys = try? JSONDecoder().decode([String].self, from: data)
    else {
      return []
    }

    return keys
  }

  func saveKeys(_ keys: [String], for kind: APIProviderKind) throws {
    try saveKeys(keys, account: account(for: kind))
  }

  func saveKeys(_ keys: [String], account: String) throws {
    let baseQuery: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
    ]

    if keys.isEmpty {
      let status = SecItemDelete(baseQuery as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw KeychainCredentialError(status: status)
      }
      return
    }

    let data = try JSONEncoder().encode(keys)
    let attributes: [CFString: Any] = [
      kSecValueData: data,
      kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let updateStatus = SecItemUpdate(
      baseQuery as CFDictionary,
      attributes as CFDictionary
    )

    if updateStatus == errSecSuccess {
      return
    }

    guard updateStatus == errSecItemNotFound else {
      throw KeychainCredentialError(status: updateStatus)
    }

    var addQuery = baseQuery
    for (key, value) in attributes {
      addQuery[key] = value
    }
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw KeychainCredentialError(status: addStatus)
    }
  }

  private func account(for kind: APIProviderKind) -> String {
    if kind == .custom {
      return CustomAPIProviderInstance.keychainAccount(
        forInstanceID: CustomAPIProviderInstance.legacyInstanceID)
    }
    return "api-provider.\(kind.rawValue).keys"
  }
}

private struct KeychainCredentialError: LocalizedError {
  let status: OSStatus

  var errorDescription: String? {
    SecCopyErrorMessageString(status, nil) as String?
  }
}
