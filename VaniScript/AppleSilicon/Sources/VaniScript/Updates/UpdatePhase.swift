import Foundation

/// High-level observable lifecycle phase of the update system.
public enum UpdatePhase: Sendable, Equatable {
    case idle
    case checking(isUserInitiated: Bool)
    case upToDate(lastChecked: Date)
    case available(UpdateDescriptor)
    case downloading(UpdateDescriptor, progress: Double, bytesReceived: UInt64, totalBytes: UInt64)
    case extracting(UpdateDescriptor, progress: Double)
    case readyToInstall(UpdateDescriptor)
    case installing(UpdateDescriptor)
    case failed(UpdateDiagnosticError)

    public var isBusy: Bool {
        switch self {
        case .checking, .downloading, .extracting, .installing:
            return true
        case .idle, .upToDate, .available, .readyToInstall, .failed:
            return false
        }
    }

    public var availableDescriptor: UpdateDescriptor? {
        switch self {
        case .available(let descriptor),
             .downloading(let descriptor, _, _, _),
             .extracting(let descriptor, _),
             .readyToInstall(let descriptor),
             .installing(let descriptor):
            return descriptor
        case .idle, .checking, .upToDate, .failed:
            return nil
        }
    }

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    public var isReadyToInstall: Bool {
        if case .readyToInstall = self { return true }
        return false
    }

    public var diagnosticError: UpdateDiagnosticError? {
        if case .failed(let error) = self { return error }
        return nil
    }
}
