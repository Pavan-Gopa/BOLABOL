import Foundation
import NativeBolabolCore
@testable import NativeBolabol
import Testing

// MARK: - S12 / ADR-031 multiple named custom API providers

private func configuredCustomSettings() -> APIProviderSettings {
    var settings = APIProviderSettings()
    settings.custom = APIProviderConfiguration(
        apiKeys: ["legacy-key"],
        textModel: "legacy-model",
        baseURL: "https://legacy.test/v1",
        name: "Legacy"
    )
    var mutable = settings
    let instance = mutable.addCustomProvider(name: "Second")
    var secondConfig = mutable.configuration(forCustomInstanceID: instance.id)
        ?? APIProviderConfiguration()
    secondConfig.apiKeys = ["second-key"]
    secondConfig.textModel = "second-model"
    secondConfig.baseURL = "https://second.test/v1"
    mutable.setConfiguration(secondConfig, forCustomInstanceID: instance.id)
    return mutable
}

// MARK: Core — migration, identity, coding

@Test
func customProviderLegacyJSONMigratesToSingleInstance() throws {
    let json = """
        {
          "custom": {"apiKeys":["k"],"textModel":"legacy-model","baseURL":"https://legacy.test/v1","name":"Legacy"}
        }
        """.data(using: .utf8)!
    let settings = try JSONDecoder().decode(APIProviderSettings.self, from: json)

    #expect(settings.customProviders.count == 1)
    let instance = try #require(settings.customProviders.first)
    #expect(instance.id == CustomAPIProviderInstance.legacyInstanceID)
    #expect(instance.engineID == "cloud-custom")
    #expect(instance.keychainAccount == "api-provider.custom.keys")
    #expect(instance.configuration.baseURL == "https://legacy.test/v1")
    #expect(instance.configuration.textModel == "legacy-model")
    #expect(instance.configuration.apiKeys == ["k"])
    #expect(instance.displayName == "Legacy")
}

@Test
func customProviderExactMatchStaysSingleKind() {
    #expect(APIProviderKind(polishingEngineID: "cloud-custom") == .custom)
    #expect(APIProviderKind(polishingEngineID: "cloud-custom-anything") == nil)
    #expect(CustomAPIProviderInstance.instanceID(forEngineID: "cloud-custom") == "legacy")
    #expect(CustomAPIProviderInstance.instanceID(forEngineID: "cloud-google") == nil)
    #expect(CustomAPIProviderInstance.instanceID(forEngineID: "cloud-custom-") == nil)
}

@Test
func customProviderTwoInstancesAppearWithDistinctEngineIDs() {
    let settings = configuredCustomSettings()
    let available = settings.availablePolishingProviders.filter { $0.kind == .custom }

    #expect(available.count == 2)
    let ids = available.map(\.engineID)
    #expect(ids.contains("cloud-custom"))
    #expect(ids.count == Set(ids).count)
    #expect(Set(available.map(\.displayName)) == ["Legacy", "Second"])

    let hud = HUDProviderListComposer.providers(apiSettings: settings)
    #expect(hud.map(\.id).contains("cloud-custom"))
    #expect(hud.filter { $0.id.hasPrefix("cloud-custom") }.count == 2)
    #expect(Set(hud.map(\.id)).count == hud.count)
}

@Test
func customProviderResolverMapsEachEngineIDToItsOwnConfiguration() throws {
    let settings = configuredCustomSettings()
    let secondID = try #require(
        settings.customProviders.first(where: { $0.id != CustomAPIProviderInstance.legacyInstanceID })?.engineID)

    let legacy = settings.resolve(engineID: "cloud-custom")
    #expect(legacy == ResolvedAPIProvider(kind: .custom, customInstanceID: "legacy"))
    let second = settings.resolve(engineID: secondID)
    #expect(second?.kind == .custom)
    #expect(second?.customInstanceID != CustomAPIProviderInstance.legacyInstanceID)

    #expect(settings.configuration(forEngineID: "cloud-custom")?.textModel == "legacy-model")
    #expect(settings.configuration(forEngineID: secondID)?.textModel == "second-model")
    #expect(settings.displayName(forEngineID: "cloud-custom") == "Legacy")
    #expect(settings.displayName(forEngineID: secondID) == "Second")
    #expect(settings.configuration(forEngineID: "cloud-custom-gone") == nil)
    #expect(settings.resolve(engineID: "cloud-google") == ResolvedAPIProvider(kind: .google))
    #expect(settings.resolve(engineID: "bogus") == nil)
}

@Test
func customProviderEncodeDecodeRoundTripPreservesInstancesAndLegacyKey() throws {
    let settings = configuredCustomSettings()
    let data = try JSONEncoder().encode(settings)
    let raw = try #require(String(data: data, encoding: .utf8))
    // Downgrade: the first instance is still written to `custom`.
    #expect(raw.contains("\"custom\""))
    #expect(raw.contains("\"customProviders\""))

    let decoded = try JSONDecoder().decode(APIProviderSettings.self, from: data)
    #expect(decoded == settings)
    #expect(decoded.customProviders.count == 2)
    #expect(decoded.custom.textModel == "legacy-model")
}

@Test
func customProviderDuplicateNamesRejectedCaseInsensitively() {
    var settings = APIProviderSettings()
    settings.custom = APIProviderConfiguration(name: "Acme")
    _ = settings.addCustomProvider(name: "Other")

    #expect(settings.isCustomNameTaken("acme") == true)
    #expect(settings.isCustomNameTaken(" ACME ") == true)
    #expect(settings.isCustomNameTaken("other") == true)
    #expect(settings.isCustomNameTaken("Another") == false)
    #expect(settings.isCustomNameTaken("") == true)
    // The instance itself is excluded, so a case-only change is allowed.
    #expect(settings.isCustomNameTaken("ACME", excludingID: "legacy") == false)

    #expect(settings.renameCustomProvider(id: "legacy", name: "OTHER") == false)
    #expect(settings.renameCustomProvider(id: "legacy", name: "  ") == false)
    #expect(settings.renameCustomProvider(id: "legacy", name: "Acme 2") == true)
    #expect(settings.custom.name == "Acme 2")

    // Adding with a taken name falls back to a unique default.
    let added = settings.addCustomProvider(name: "ACME 2")
    #expect(added.configuration.name.lowercased() != "acme 2")
    #expect(settings.customProviders.count == 3)
}

@Test
func customProviderDefaultNameIsUnique() {
    var settings = APIProviderSettings()
    settings.custom = APIProviderConfiguration(name: "Custom 2")
    #expect(settings.defaultCustomName(language: .english) == "Custom 3")
    #expect(AppText.localized(.customProviderDefaultName, language: .english).contains("%d"))
}

@Test
func customProviderOptionsResolvePerInstance() {
    let settings = configuredCustomSettings()
    let provider = PolishingModelOptionsProvider(apiSettings: settings)
    let secondID = settings.customProviders.first(
        where: { $0.id != CustomAPIProviderInstance.legacyInstanceID })!.engineID

    #expect(provider.providerModelOptions(forEngineID: "cloud-custom", favorites: []).map(\.id) == ["legacy-model"])
    #expect(provider.providerModelOptions(forEngineID: secondID, favorites: []).map(\.id) == ["second-model"])
    #expect(provider.availableModels(forEngineID: secondID).map(\.id) == ["second-model"])
    #expect(provider.modelDisplayName(id: "second-model", engineID: "second-model") == "second-model")
    #expect(provider.providerModelOptions(forEngineID: "cloud-custom-gone", favorites: []).isEmpty)
    #expect(provider.availableModels(forEngineID: "bogus").isEmpty)
}

// MARK: Store — keychain, selection repair, persistence isolation

private final class InMemoryAPIProviderCredentialStore: APIProviderCredentialStoring {
    private let lock = NSLock()
    private var accounts: [String: [String]]

    init(accounts: [String: [String]] = [:]) {
        self.accounts = accounts
    }

    private func accountForKind(_ kind: APIProviderKind) -> String {
        if kind == .custom {
            return CustomAPIProviderInstance.keychainAccount(
                forInstanceID: CustomAPIProviderInstance.legacyInstanceID)
        }
        return "api-provider.\(kind.rawValue).keys"
    }

    func loadKeys(for kind: APIProviderKind) -> [String] {
        loadKeys(account: accountForKind(kind))
    }

    func saveKeys(_ keys: [String], for kind: APIProviderKind) throws {
        try saveKeys(keys, account: accountForKind(kind))
    }

    func loadKeys(account: String) -> [String] {
        lock.withLock { accounts[account] ?? [] }
    }

    func saveKeys(_ keys: [String], account: String) throws {
        lock.withLock {
            if keys.isEmpty {
                accounts.removeValue(forKey: account)
            } else {
                accounts[account] = keys
            }
        }
    }
}

private func isolatedSuite() throws -> (UserDefaults, String) {
    let name = "bolabol-s12-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    return (defaults, name)
}

private func tempModelsDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "bolabol-s12-models-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
@Test
func customProviderRemovalDeletesKeychainAndResetsSelection() throws {
    let (defaults, suite) = try isolatedSuite()
    defer { defaults.removePersistentDomain(forName: suite) }
    let modelsDir = try tempModelsDirectory()
    defer { try? FileManager.default.removeItem(at: modelsDir) }
    let credentials = InMemoryAPIProviderCredentialStore()

    let store = PolishingEngineStore(
        userDefaults: defaults, modelsDirectory: modelsDir, credentialStore: credentials)

    // Configure the legacy instance, then add and configure a second one.
    var legacy = store.apiSettings.custom
    legacy.apiKeys = ["legacy-key"]
    legacy.textModel = "legacy-model"
    legacy.baseURL = "https://legacy.test/v1"
    legacy.name = "Legacy"
    store.updateAPIConfiguration(legacy, for: .custom)

    let second = store.addCustomProvider(name: "Second")
    let secondConfig = APIProviderConfiguration(
        apiKeys: ["second-key"], textModel: "second-model",
        baseURL: "https://second.test/v1", name: "Second")
    _ = store.updateAPIConfiguration(secondConfig, forEngineID: second.engineID)


    let ids = Set(store.descriptors.map(\.id))
    #expect(ids.contains("cloud-custom"))
    #expect(ids.contains(second.engineID))
    #expect(credentials.loadKeys(account: second.keychainAccount) == ["second-key"])

    store.selectAPIProvider(engineID: second.engineID)
    #expect(store.selectedEngineID == second.engineID)

    store.removeCustomProvider(id: second.id)

    // Keychain item deleted, selection repaired to disabled, legacy untouched.
    #expect(credentials.loadKeys(account: second.keychainAccount).isEmpty)
    #expect(store.selectedEngineID == PolishingEngineStore.disabledEngineID)
    #expect(!store.descriptors.map(\.id).contains(second.engineID))
    #expect(store.descriptors.map(\.id).contains("cloud-custom"))
    #expect(store.apiSettings.custom.apiKeys == ["legacy-key"])
    #expect(credentials.loadKeys(account: "api-provider.custom.keys") == ["legacy-key"])
}

@MainActor
@Test
func customProviderLegacyStoredSelectionKeepsWorking() throws {
    let (defaults, suite) = try isolatedSuite()
    defer { defaults.removePersistentDomain(forName: suite) }
    let modelsDir = try tempModelsDirectory()
    defer { try? FileManager.default.removeItem(at: modelsDir) }

    // Legacy on-disk format: only `custom`, no `customProviders` list.
    let legacyJSON = """
        {"custom":{"apiKeys":[],"textModel":"legacy-model","baseURL":"https://legacy.test/v1","name":"Legacy"}}
        """.data(using: .utf8)!
    defaults.set(legacyJSON, forKey: "polishing.apiProviderSettings")
    defaults.set("cloud-custom", forKey: "polishing.selectedEngineID")

    let credentials = InMemoryAPIProviderCredentialStore(
        accounts: ["api-provider.custom.keys": ["legacy-key"]])
    let store = PolishingEngineStore(
        userDefaults: defaults, modelsDirectory: modelsDir, credentialStore: credentials)

    #expect(store.selectedEngineID == "cloud-custom")
    #expect(store.apiSettings.customProviders.count == 1)
    #expect(store.apiSettings.custom.apiKeys == ["legacy-key"])
    #expect(store.preparationSnapshot.message?.contains("Legacy") == true)
    let engine = try #require(store.engine(for: "cloud-custom"))
    #expect(engine.id == "cloud-custom")
    #expect((engine as? CloudTextPolishingEngine)?.displayName == "Legacy")
}

@MainActor
@Test
func customProviderKeysNeverEnterUserDefaultsJSON() throws {
    let (defaults, suite) = try isolatedSuite()
    defer { defaults.removePersistentDomain(forName: suite) }
    let modelsDir = try tempModelsDirectory()
    defer { try? FileManager.default.removeItem(at: modelsDir) }
    let credentials = InMemoryAPIProviderCredentialStore()
    let store = PolishingEngineStore(
        userDefaults: defaults, modelsDirectory: modelsDir, credentialStore: credentials)

    let secret = "sk-s12-never-persist-001"
    var legacy = store.apiSettings.custom
    legacy.apiKeys = [secret]
    legacy.textModel = "legacy-model"
    legacy.baseURL = "https://legacy.test/v1"
    store.updateAPIConfiguration(legacy, for: .custom)
    let second = store.addCustomProvider(name: "Second")
    let secondConfig = APIProviderConfiguration(
        apiKeys: [secret + "-2"], textModel: "second-model",
        baseURL: "https://second.test/v1", name: "Second")
    _ = store.updateAPIConfiguration(secondConfig, forEngineID: second.engineID)

    for (key, value) in defaults.dictionaryRepresentation() {
        guard let data = value as? Data,
            let text = String(data: data, encoding: .utf8)
        else { continue }
        #expect(!text.contains(secret), "UserDefaults entry \(key) leaks API key material")
    }
    #expect(credentials.loadKeys(account: "api-provider.custom.keys") == [secret])
    #expect(credentials.loadKeys(account: second.keychainAccount) == [secret + "-2"])
}

@MainActor
@Test
func customProviderHydrateCoversNewInstanceAccounts() throws {
    let (defaults, suite) = try isolatedSuite()
    defer { defaults.removePersistentDomain(forName: suite) }
    let modelsDir = try tempModelsDirectory()
    defer { try? FileManager.default.removeItem(at: modelsDir) }

    let settingsJSON = """
        {"customProviders":[
          {"id":"legacy","configuration":{"apiKeys":[],"textModel":"legacy-model","baseURL":"https://legacy.test/v1","name":"Legacy"}},
          {"id":"uuid-2","configuration":{"apiKeys":[],"textModel":"second-model","baseURL":"https://second.test/v1","name":"Second"}}
        ]}
        """.data(using: .utf8)!
    defaults.set(settingsJSON, forKey: "polishing.apiProviderSettings")

    let credentials = InMemoryAPIProviderCredentialStore(accounts: [
        "api-provider.custom.keys": ["legacy-key"],
        "api-provider.custom.uuid-2.keys": ["second-key"],
    ])
    let store = PolishingEngineStore(
        userDefaults: defaults, modelsDirectory: modelsDir, credentialStore: credentials)

    #expect(store.apiSettings.configuration(forEngineID: "cloud-custom")?.apiKeys == ["legacy-key"])
    #expect(
        store.apiSettings.configuration(forEngineID: "cloud-custom-uuid-2")?.apiKeys == ["second-key"])
    let ids = Set(store.descriptors.map(\.id))
    #expect(ids.contains("cloud-custom"))
    #expect(ids.contains("cloud-custom-uuid-2"))
}

@MainActor
@Test
func customProviderRemovalClearsTranslationAndResolvesNilForMissingInstance() throws {
    let (defaults, suite) = try isolatedSuite()
    defer { defaults.removePersistentDomain(forName: suite) }
    let modelsDir = try tempModelsDirectory()
    defer { try? FileManager.default.removeItem(at: modelsDir) }
    let credentials = InMemoryAPIProviderCredentialStore()
    let store = PolishingEngineStore(
        userDefaults: defaults, modelsDirectory: modelsDir, credentialStore: credentials)

    var legacy = store.apiSettings.custom
    legacy.apiKeys = ["legacy-key"]
    legacy.textModel = "legacy-model"
    legacy.baseURL = "https://legacy.test/v1"
    legacy.name = "Legacy"
    store.updateAPIConfiguration(legacy, for: .custom)

    let second = store.addCustomProvider(name: "Second")
    let secondConfig = APIProviderConfiguration(
        apiKeys: ["second-key"], textModel: "second-model",
        baseURL: "https://second.test/v1", name: "Second")
    _ = store.updateAPIConfiguration(secondConfig, forEngineID: second.engineID)

    // Optional-wrapped so this compiles before and after `engine(for:)`
    // becomes nil for a missing custom instance.
    let beforeRemoval: (any PolishingEngine)? = store.engine(for: second.engineID)
    #expect(beforeRemoval != nil)

    // Translation pointing at the removed instance is cleared …
    defaults.set(second.engineID, forKey: "translation.providerID")
    store.removeCustomProvider(id: second.id)
    #expect(defaults.string(forKey: "translation.providerID") == nil)
    // … and the missing instance no longer resolves, so the pipeline
    // active-engine fallback runs.
    let afterRemoval: (any PolishingEngine)? = store.engine(for: second.engineID)
    #expect(afterRemoval == nil)

    // Translation pointing elsewhere survives an unrelated removal.
    let third = store.addCustomProvider(name: "Third")
    defaults.set("cloud-custom", forKey: "translation.providerID")
    store.removeCustomProvider(id: third.id)
    #expect(defaults.string(forKey: "translation.providerID") == "cloud-custom")
}

// MARK: QA — upgrade and consumer lifecycle paths

@MainActor
@Test(arguments: [
    #"{"custom":{"apiKeys":[],"apiKey":"","textModel":"legacy-model","baseURL":"https://legacy.test/v1","name":""}}"#,
    #"{"custom":{"apiKeys":[],"apiKey":"","textModel":"legacy-model","baseURL":"https://legacy.test/v1","name":"My Endpoint"}}"#,
    #"{"custom":{"apiKeys":[],"apiKey":"","textModel":"legacy-model","name":"Not Yet Configured"}}"#,
])
func customProviderLegacyStoreUpgradeRoundTripsWithoutLosingCredentials(json: String) throws {
    let (defaults, suite) = try isolatedSuite()
    defer { defaults.removePersistentDomain(forName: suite) }
    let modelsDir = try tempModelsDirectory()
    defer { try? FileManager.default.removeItem(at: modelsDir) }
    let original = try JSONDecoder().decode(APIProviderSettings.self, from: Data(json.utf8))
    let keys = ["legacy-upgrade-secret", "#DISABLED#legacy-disabled-secret"]
    let credentials = InMemoryAPIProviderCredentialStore(
        accounts: ["api-provider.custom.keys": keys])
    defaults.set(Data(json.utf8), forKey: "polishing.apiProviderSettings")
    defaults.set("cloud-custom", forKey: "polishing.selectedEngineID")
    defaults.set("cloud-custom", forKey: "polishing.lastNonDisabledEngineID")
    defaults.set("cloud-custom", forKey: "translation.providerID")

    let store = PolishingEngineStore(
        userDefaults: defaults, modelsDirectory: modelsDir, credentialStore: credentials)
    let migrated = try #require(store.apiSettings.customProviders.first)
    #expect(migrated.id == CustomAPIProviderInstance.legacyInstanceID)
    #expect(migrated.configuration.name == original.custom.name)
    #expect(migrated.configuration.baseURL == original.custom.baseURL)
    #expect(migrated.configuration.textModel == original.custom.textModel)
    #expect(migrated.configuration.apiKeys == keys)
    #expect(credentials.loadKeys(account: migrated.keychainAccount) == keys)
    let hasBaseURL = !original.custom.baseURL.isEmpty
    #expect(store.selectedEngineID == (hasBaseURL ? "cloud-custom" : PolishingEngineStore.disabledEngineID))
    #expect(store.descriptors.contains { $0.id == "cloud-custom" } == hasBaseURL)
    #expect(defaults.string(forKey: "polishing.lastNonDisabledEngineID") == "cloud-custom")
    #expect(defaults.string(forKey: "translation.providerID") == "cloud-custom")

    let saved = try #require(defaults.data(forKey: "polishing.apiProviderSettings"))
    let savedSettings = try JSONDecoder().decode(APIProviderSettings.self, from: saved)
    #expect(savedSettings.customProviders.map(\.id) == [migrated.id])
    #expect(savedSettings.custom.apiKeys.isEmpty)
    let raw = try #require(String(data: saved, encoding: .utf8))
    for key in keys {
        #expect(!raw.contains(key))
    }
    let reloaded = PolishingEngineStore(
        userDefaults: defaults, modelsDirectory: modelsDir, credentialStore: credentials)
    #expect(reloaded.apiSettings == store.apiSettings)
    #expect(reloaded.selectedEngineID == store.selectedEngineID)
}

@MainActor
@Test
func customProviderStoreLifecycleKeepsSurvivorsAndRepairsBothSelections() throws {
    let (defaults, suite) = try isolatedSuite()
    defer { defaults.removePersistentDomain(forName: suite) }
    let modelsDir = try tempModelsDirectory()
    defer { try? FileManager.default.removeItem(at: modelsDir) }
    let credentials = InMemoryAPIProviderCredentialStore()
    let store = PolishingEngineStore(
        userDefaults: defaults, modelsDirectory: modelsDir, credentialStore: credentials)
    store.updateAPIConfiguration(
        APIProviderConfiguration(
            apiKeys: ["first-secret"], textModel: "shared-model",
            baseURL: "https://shared.test/v1", name: "Custom 3"),
        for: .custom)
    let first = try #require(store.apiSettings.customProviders.first)
    let second = store.addCustomProvider(name: "  Acme  ")
    let third = store.addCustomProvider(name: "Third")
    for (instance, key) in [(second, "second-secret"), (third, "third-secret")] {
        var config = instance.configuration
        config.apiKeys = [key]
        config.baseURL = "https://shared.test/v1"
        config.textModel = "shared-model"
        #expect(store.updateAPIConfiguration(config, forEngineID: instance.engineID))
    }
    let originalIDs = [first, second, third].map(\.engineID)
    #expect(Set(originalIDs).count == 3)
    #expect(Set([first, second, third].map(\.keychainAccount)).count == 3)
    #expect(store.apiSettings.customInstance(id: second.id)?.configuration.name == "Acme")
    #expect(HUDProviderListComposer.providers(apiSettings: store.apiSettings).map(\.id)
        == [HUDProviderListComposer.defaultLocalEngineID] + originalIDs)
    let beforeRejectedRename = store.apiSettings
    for name in ["Custom 3", "  cUsToM 3 \n", "\t \n"] {
        #expect(!store.renameCustomProvider(id: second.id, name: name))
        #expect(store.apiSettings == beforeRejectedRename)
    }
    #expect(store.renameCustomProvider(id: second.id, name: "  Renamed Endpoint \n"))
    #expect(store.apiSettings.customInstance(id: second.id)?.configuration.name == "Renamed Endpoint")
    #expect(HUDProviderListComposer.providers(apiSettings: store.apiSettings).map(\.id)
        == [HUDProviderListComposer.defaultLocalEngineID] + originalIDs)

    store.selectAPIProvider(engineID: second.engineID)
    defaults.set(second.engineID, forKey: "translation.providerID")
    #expect(defaults.string(forKey: "polishing.lastNonDisabledEngineID") == second.engineID)
    #expect((store.activeEngine as? CloudTextPolishingEngine)?.displayName == "Renamed Endpoint")
    store.removeCustomProvider(id: second.id)
    #expect(store.selectedEngineID == PolishingEngineStore.disabledEngineID)
    #expect(defaults.string(forKey: "polishing.selectedEngineID") == PolishingEngineStore.disabledEngineID)
    #expect(defaults.string(forKey: "polishing.lastNonDisabledEngineID") == nil)
    #expect(defaults.string(forKey: "translation.providerID") == nil)
    #expect(store.engine(for: second.engineID) == nil)
    #expect(credentials.loadKeys(account: second.keychainAccount).isEmpty)

    // Removing the middle entry leaves "Custom 3" occupied despite list count 2.
    let replacement = store.addCustomProvider(name: " \n ")
    #expect(!originalIDs.contains(replacement.engineID))
    #expect(![first, second, third].map(\.keychainAccount).contains(replacement.keychainAccount))
    #expect(replacement.displayName.lowercased() != first.displayName.lowercased())
    #expect(credentials.loadKeys(account: replacement.keychainAccount).isEmpty)
    let duplicate = store.addCustomProvider(name: "  THIRD ")
    #expect(duplicate.displayName.lowercased() != third.displayName.lowercased())
    let names = store.apiSettings.customProviders.map { $0.displayName.lowercased() }
    #expect(names.count == Set(names).count)
    #expect(HUDProviderListComposer.providers(apiSettings: store.apiSettings).map(\.id)
        == [HUDProviderListComposer.defaultLocalEngineID, first.engineID, third.engineID])
    #expect(credentials.loadKeys(account: first.keychainAccount) == ["first-secret"])
    #expect(credentials.loadKeys(account: third.keychainAccount) == ["third-secret"])

    let saved = try #require(defaults.data(forKey: "polishing.apiProviderSettings"))
    let decoded = try JSONDecoder().decode(APIProviderSettings.self, from: saved)
    #expect(decoded.customProviders.allSatisfy { $0.configuration.apiKeys.isEmpty })
    let raw = try #require(String(data: saved, encoding: .utf8))
    for secret in ["first-secret", "second-secret", "third-secret"] {
        #expect(!raw.contains(secret))
    }
    // Decode only the old `custom` key, as a downgraded build would.
    let object = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
    let legacyObject = try #require(object["custom"] as? [String: Any])
    let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
    let downgrade = try JSONDecoder().decode(APIProviderConfiguration.self, from: legacyData)
    #expect(downgrade == decoded.customProviders.first?.configuration)
    #expect(downgrade.name == "Custom 3")
    #expect(downgrade.apiKeys.isEmpty)
    #expect(downgrade.apiKey.isEmpty)

    let reloaded = PolishingEngineStore(
        userDefaults: defaults, modelsDirectory: modelsDir, credentialStore: credentials)
    #expect(reloaded.apiSettings == store.apiSettings)
    #expect(reloaded.selectedEngineID == PolishingEngineStore.disabledEngineID)
    #expect(reloaded.apiSettings.customInstance(id: second.id) == nil)
    #expect(reloaded.engine(for: second.engineID) == nil)
    #expect(HUDProviderListComposer.providers(apiSettings: reloaded.apiSettings)
        == HUDProviderListComposer.providers(apiSettings: store.apiSettings))
}

@MainActor
@Test
func customProviderSameEndpointCacheAndModelChangesRemainInstanceSpecific() throws {
    let (defaults, suite) = try isolatedSuite()
    defer { defaults.removePersistentDomain(forName: suite) }
    let modelsDir = try tempModelsDirectory()
    defer { try? FileManager.default.removeItem(at: modelsDir) }
    let credentials = InMemoryAPIProviderCredentialStore()
    let store = PolishingEngineStore(
        userDefaults: defaults, modelsDirectory: modelsDir, credentialStore: credentials)
    store.updateAPIConfiguration(
        APIProviderConfiguration(
            apiKeys: ["alpha-secret"], textModel: "shared-model",
            baseURL: "https://same.test/v1", name: "Alpha"),
        for: .custom)
    let beta = store.addCustomProvider(name: "Beta")
    var betaConfig = APIProviderConfiguration(
        apiKeys: ["beta-secret"], textModel: "shared-model",
        baseURL: "https://same.test/v1", name: "Beta")
    #expect(store.updateAPIConfiguration(betaConfig, forEngineID: beta.engineID))
    for _ in 0..<2 {
        let alphaEngine = try #require(store.engine(for: "cloud-custom") as? CloudTextPolishingEngine)
        let betaEngine = try #require(store.engine(for: beta.engineID) as? CloudTextPolishingEngine)
        #expect(alphaEngine.id != betaEngine.id)
        #expect(alphaEngine.configuration.apiKeys == ["alpha-secret"])
        #expect(betaEngine.configuration.apiKeys == ["beta-secret"])
        #expect(alphaEngine.displayName == "Alpha")
        #expect(betaEngine.displayName == "Beta")
    }
    store.selectAPIProvider(engineID: beta.engineID)
    betaConfig.textModel = "beta-new-model"
    betaConfig.apiKeys = ["beta-rotated-secret"]
    #expect(store.updateAPIConfiguration(betaConfig, forEngineID: beta.engineID))
    #expect(store.renameCustomProvider(id: beta.id, name: "Beta Renamed"))
    let betaEngine = try #require(store.activeEngine as? CloudTextPolishingEngine)
    let alphaEngine = try #require(store.engine(for: "cloud-custom") as? CloudTextPolishingEngine)
    #expect(betaEngine.configuration.textModel == "beta-new-model")
    #expect(betaEngine.configuration.apiKeys == ["beta-rotated-secret"])
    #expect(betaEngine.displayName == "Beta Renamed")
    #expect(alphaEngine.configuration.textModel == "shared-model")
    #expect(alphaEngine.configuration.apiKeys == ["alpha-secret"])
    let options = PolishingModelOptionsProvider(apiSettings: store.apiSettings)
    #expect(options.providerModelOptions(forEngineID: beta.engineID, favorites: []).map(\.id)
        == ["beta-new-model"])
    #expect(options.providerModelOptions(forEngineID: "cloud-custom", favorites: []).map(\.id)
        == ["shared-model"])
    #expect(store.preparationSnapshot.message?.contains("Beta Renamed") == true)
    #expect(HUDProviderListComposer.providers(apiSettings: store.apiSettings).map(\.displayName)
        == ["Local.AI", "Alpha", "Beta Renamed"])
}

@Test
func customProviderFavouriteFromOneInstanceDoesNotAppearInSiblingMenu() throws {
    let (defaults, suite) = try isolatedSuite()
    defer { defaults.removePersistentDomain(forName: suite) }
    var settings = APIProviderSettings(
        custom: APIProviderConfiguration(
            apiKeys: ["alpha-secret"], textModel: "shared-model",
            baseURL: "https://same.test/v1", name: "Alpha"))
    let beta = settings.addCustomProvider(name: "Beta")
    let configured = settings.setConfiguration(
        APIProviderConfiguration(
            apiKeys: ["beta-secret"], textModel: "shared-model",
            baseURL: "https://same.test/v1", name: "Beta"),
        forEngineID: beta.engineID)
    #expect(configured)
    // Star through Alpha's engine-scoped store, as the model picker does,
    // then feed each menu its own engine's favourites (picker/HUD path).
    _ = FavoriteModelsStore.toggleFavorite("alpha-only-model", engineID: "cloud-custom", defaults: defaults)
    let alphaFavorites = FavoriteModelsStore.loadFavorites(engineID: "cloud-custom", defaults: defaults)
    let betaFavorites = FavoriteModelsStore.loadFavorites(engineID: beta.engineID, defaults: defaults)
    #expect(alphaFavorites.contains("alpha-only-model"))
    #expect(!betaFavorites.contains("alpha-only-model"))
    let options = PolishingModelOptionsProvider(apiSettings: settings)
    #expect(options.providerModelOptions(forEngineID: "cloud-custom", favorites: alphaFavorites)
        .contains { $0.id == "alpha-only-model" })
    #expect(!options.providerModelOptions(forEngineID: beta.engineID, favorites: betaFavorites)
        .contains { $0.id == "alpha-only-model" },
        "A favourite selected in Alpha must not populate Beta's HUD/translation model menu")
}

@Test
func customProviderLegacyFavoritesFallBackToGlobalUntilScopedWrite() throws {
    let (defaults, suite) = try isolatedSuite()
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["legacy-fav"], forKey: "favorite.cloud.model.ids")
    // Built-ins keep the global key unchanged.
    #expect(FavoriteModelsStore.loadFavorites(engineID: "cloud-google", defaults: defaults) == ["legacy-fav"])
    // Legacy custom falls back to the global set while its scoped key is absent …
    #expect(FavoriteModelsStore.loadFavorites(engineID: "cloud-custom", defaults: defaults) == ["legacy-fav"])
    // … while a non-legacy sibling starts empty.
    #expect(FavoriteModelsStore.loadFavorites(engineID: "cloud-custom-sibling", defaults: defaults).isEmpty)
    // First toggle writes the scoped key (seeded from the fallback) …
    let afterToggle = FavoriteModelsStore.toggleFavorite("new-fav", engineID: "cloud-custom", defaults: defaults)
    #expect(afterToggle == ["legacy-fav", "new-fav"])
    #expect(Set(defaults.stringArray(forKey: "favorite.cloud.model.ids.cloud-custom") ?? []) == ["legacy-fav", "new-fav"])
    // … leaves the global key untouched, and later loads use the scoped key.
    #expect(Set(defaults.stringArray(forKey: "favorite.cloud.model.ids") ?? []) == ["legacy-fav"])
    defaults.set([], forKey: "favorite.cloud.model.ids")
    #expect(FavoriteModelsStore.loadFavorites(engineID: "cloud-custom", defaults: defaults) == ["legacy-fav", "new-fav"])
}
