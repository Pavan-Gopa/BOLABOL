import Foundation

public struct ModelPreparationSnapshot: Equatable, Sendable {
    public enum Phase: String, Equatable, Sendable {
        case notReady
        case downloading
        case loading
        case ready
        case failed
    }

    public var phase: Phase
    public var progressFraction: Double?
    public var message: String?
    public var modelDirectory: URL?
    public var diagnostics: EngineDiagnostics?

    public init(
        phase: Phase,
        progressFraction: Double? = nil,
        message: String? = nil,
        modelDirectory: URL? = nil,
        diagnostics: EngineDiagnostics? = nil
    ) {
        self.phase = phase
        self.progressFraction = progressFraction.map(Self.clamp)
        self.message = message
        self.modelDirectory = modelDirectory
        self.diagnostics = diagnostics
    }

    public static func notReady(
        modelDirectory: URL? = nil,
        message: String? = nil
    ) -> ModelPreparationSnapshot {
        ModelPreparationSnapshot(
            phase: .notReady,
            message: message,
            modelDirectory: modelDirectory
        )
    }

    public static func downloading(
        progressFraction: Double?,
        modelDirectory: URL? = nil,
        message: String? = nil
    ) -> ModelPreparationSnapshot {
        ModelPreparationSnapshot(
            phase: .downloading,
            progressFraction: progressFraction,
            message: message,
            modelDirectory: modelDirectory
        )
    }

    public static func loading(
        modelDirectory: URL? = nil,
        message: String? = nil
    ) -> ModelPreparationSnapshot {
        ModelPreparationSnapshot(
            phase: .loading,
            message: message,
            modelDirectory: modelDirectory
        )
    }

    public static func ready(
        modelDirectory: URL? = nil,
        diagnostics: EngineDiagnostics? = nil,
        message: String? = nil
    ) -> ModelPreparationSnapshot {
        ModelPreparationSnapshot(
            phase: .ready,
            message: message,
            modelDirectory: modelDirectory,
            diagnostics: diagnostics
        )
    }

    public static func failed(
        message: String,
        modelDirectory: URL? = nil
    ) -> ModelPreparationSnapshot {
        ModelPreparationSnapshot(
            phase: .failed,
            message: message,
            modelDirectory: modelDirectory
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
