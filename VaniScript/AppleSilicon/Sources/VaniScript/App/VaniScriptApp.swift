import AppKit
import SwiftUI
import VaniScriptCore
import VaniScriptRuntime

struct BatchConfigurationKey: Equatable {
    static let plannerVersion = "batch-v2"
    static let silencePlannerVersion = "smart-audio-v1"

    let plannerVersion: String
    let silencePlannerVersion: String
    let transcriptionProvider: String
    let effectiveTranscriptionModel: String
    let sourceLanguage: String
    let chunkDurationMin: Int
    let sliceMode: SliceMode
    let silenceThreshDb: Int
    let minSilenceMs: Int
    let requireCanonicalNames: Bool

    init(settings: AppSettings) {
        let provider = settings.transcriptionProvider.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuredModel = settings.transcriptionModel(for: provider)
        plannerVersion = Self.plannerVersion
        silencePlannerVersion = Self.silencePlannerVersion
        transcriptionProvider = provider
        effectiveTranscriptionModel = configuredModel.isEmpty ? provider : configuredModel
        sourceLanguage = NativeLanguagePolicy.autoCode
        chunkDurationMin = settings.chunkDurationMin
        sliceMode = settings.sliceMode
        silenceThreshDb = settings.silenceThreshDb
        minSilenceMs = settings.minSilenceMs
        requireCanonicalNames = settings.requireCanonicalNames
    }

    var identifier: String {
        [
            plannerVersion,
            silencePlannerVersion,
            transcriptionProvider,
            effectiveTranscriptionModel,
            sourceLanguage,
            String(chunkDurationMin),
            sliceMode.rawValue,
            String(silenceThreshDb),
            String(minSilenceMs),
            requireCanonicalNames ? "1" : "0"
        ].joined(separator: "|")
    }
}

@main
struct VaniScriptApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var workflowStore: WorkflowStore
    @StateObject private var batchStore: BatchTranscriptionStore
    @StateObject private var updateCoordinator = UpdateCoordinator()

    init() {
        let workflowStore = WorkflowStore()
        let batchStore = Self.makeBatchStore(workflowStore: workflowStore)
        _workflowStore = StateObject(wrappedValue: workflowStore)
        _batchStore = StateObject(wrappedValue: batchStore)
    }

    var body: some Scene {
        WindowGroup(AppIdentity.displayName) {
            ContentView()
                .environmentObject(workflowStore)
                .environmentObject(updateCoordinator)
                .environmentObject(batchStore)
                .frame(minWidth: 980, minHeight: 680)
                .task {
                    updateCoordinator.setReadinessProvider(workflowStore)
                    updateCoordinator.start()
                    updateCoordinator.checkAndSurfacePostRelaunchReceipt(workflowStore: workflowStore)
                    workflowStore.reconcileLocalModelStates()
                    workflowStore.startFirstRunOnboardingIfNeeded()
                    workflowStore.configureMcpServer()
                    await batchStore.restore()
                }
                .onChange(of: BatchConfigurationKey(settings: workflowStore.settings)) {
                    Task { await batchStore.reconfigure() }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    workflowStore.reconcileLocalModelStates()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updateCoordinator.checkForUpdates()
                }
                .disabled(updateCoordinator.phase.isBusy)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(workflowStore)
                .environmentObject(batchStore)
                .environmentObject(updateCoordinator)
                .frame(width: 760, height: 620)
                .task {
                    workflowStore.reconcileLocalModelStates()
                    workflowStore.configureMcpServer()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    workflowStore.reconcileLocalModelStates()
                }
        }
    }

    @MainActor
    private static func batchStartBlockMessage(
        settings: AppSettings,
        providerID: String,
        readiness: NativeProcessingReadinessResult
    ) -> String? {
        guard !readiness.canTranscribe else { return nil }
        let descriptor = NativeModelCatalog.descriptor(for: providerID)
            ?? NativeModelCatalog.activeLocalASRModel(settings: settings, providerID: providerID)?.descriptor
        let requiresExplicitLanguage = descriptor?.capabilities.supportsAutoLanguageDetect == false
            || readiness.transcriptionMessage.contains("requires an explicit source language")
        guard requiresExplicitLanguage else { return readiness.transcriptionMessage }
        let modelName = descriptor?.displayName ?? providerID
        return "\(modelName) cannot run mixed-language Batch because it requires an explicit source language. Batch uses Auto Detect; choose Whisper Large v3, Parakeet TDT 0.6B v3, or a cloud provider."
    }

    private static func makeBatchStore(workflowStore: WorkflowStore) -> BatchTranscriptionStore {
        do {
            try AppStoragePaths.prepareBatchStorage()
            let repository = try SQLiteBatchJobRepository(url: AppStoragePaths.batchDatabaseURL())
            let profileStore = SecurityScopedFolderStore(profilesURL: AppStoragePaths.batchFolderProfilesURL())
            let currentConfiguration: BatchTranscriptionStore.ConfigurationProvider = { [weak workflowStore] in
                guard let workflowStore else {
                    preconditionFailure("WorkflowStore must outlive the batch runtime.")
                }
                let settings = workflowStore.settings
                let key = BatchConfigurationKey(settings: settings)
                let providerID = key.transcriptionProvider
                let providerName = ProviderRegistry.availableTranscriptionProviders(settings: settings)
                    .first(where: { $0.id == providerID })?.label ?? providerID
                let readiness = NativeProcessingReadiness.evaluate(
                    settings: settings,
                    sourceLang: NativeLanguagePolicy.autoCode,
                    targetLang: NativeLanguagePolicy.keepOriginalCode,
                    transcriptionProvider: providerID,
                    translationProvider: ""
                )
                let configuration = BatchTranscriptionConfiguration(
                    identifier: key.identifier,
                    sourceLanguage: NativeLanguagePolicy.autoCode
                )
                return BatchTranscriptionStore.RuntimeConfiguration(
                    configuration: configuration,
                    providerDisplayName: providerName,
                    transcriber: workflowStore.sharedProcessingPipeline.makeBatchAudioTranscriber(
                        workspaceRoot: AppStoragePaths.batchWorkspacesDirectory(),
                        sourceLang: NativeLanguagePolicy.autoCode,
                        settings: settings,
                        providerID: providerID
                    ),
                    requireCanonicalNames: settings.requireCanonicalNames,
                    startBlockMessage: Self.batchStartBlockMessage(
                        settings: settings,
                        providerID: providerID,
                        readiness: readiness
                    )
                )
            }
            let initial = currentConfiguration()
            final class RuntimeBridge: @unchecked Sendable {
                weak var store: BatchTranscriptionStore?
            }
            let bridge = RuntimeBridge()
            let coordinator = BatchTranscriptionCoordinator(
                repository: repository,
                configuration: initial.configuration,
                transcriber: initial.transcriber,
                writer: AtomicCompanionWriter(),
                maxAttempts: 3,
                eventHandler: { event in
                    await bridge.store?.record(event)
                }
            )
            let watcher = WatchedFolderService(
                store: profileStore,
                repository: repository,
                configuration: initial.configuration,
                stabilityProbe: FileStabilityProbe(),
                requireCanonicalNames: initial.requireCanonicalNames,
                didReconcile: { event in
                    await MainActor.run { bridge.store?.recordReconciliation(event) }
                }
            )
            let store = BatchTranscriptionStore(
                profileStore: profileStore,
                repository: repository,
                watcher: watcher,
                coordinator: coordinator,
                configuration: initial.configuration,
                providerDisplayName: initial.providerDisplayName,
                requireCanonicalNames: initial.requireCanonicalNames,
                startBlockMessage: initial.startBlockMessage,
                configurationProvider: currentConfiguration
            )
            bridge.store = store
            return store
        } catch {
            return .disabled(message: "Batch transcription is unavailable: \(error.localizedDescription)")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NativeFontRegistry.registerVisualEditorFonts()

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Dynamic Dock Icon setup to bypass macOS icon caching lag
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        } else if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                  let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
