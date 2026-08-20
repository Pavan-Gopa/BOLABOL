import Foundation
import Testing
@testable import VaniScriptRuntime

@Suite("Transcription scheduler")
struct TranscriptionSchedulerTests {
    @Test("runs one inference and prioritizes queued manual work")
    func manualPriorityAndConcurrencyOne() async throws {
        let scheduler = TranscriptionScheduler()
        let gate = SchedulerGate()
        let log = SchedulerLog()

        let active = Task {
            try await scheduler.run(priority: .background) {
                await log.started("active")
                await gate.wait()
                await log.finished("active")
            }
        }
        await gate.waitUntilEntered()
        let background = Task {
            try await scheduler.run(priority: .background) {
                await log.started("background")
                await log.finished("background")
            }
        }
        let manual = Task {
            try await scheduler.run(priority: .manual) {
                await log.started("manual")
                await log.finished("manual")
            }
        }
        await Task.yield()
        await gate.open()
        try await active.value
        try await manual.value
        try await background.value

        #expect(await log.starts == ["active", "manual", "background"])
        #expect(await log.maximumActive == 1)
    }

    @Test("cancelled queued work never runs")
    func queuedCancellation() async throws {
        let scheduler = TranscriptionScheduler()
        let gate = SchedulerGate()
        let log = SchedulerLog()
        let active = Task {
            try await scheduler.run(priority: .background) {
                await gate.wait()
            }
        }
        await gate.waitUntilEntered()
        let cancelled = Task {
            try await scheduler.run(priority: .background) {
                await log.started("cancelled")
            }
        }
        await Task.yield()
        cancelled.cancel()
        await gate.open()
        try await active.value
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(await log.starts.isEmpty)
    }

    @Test("cancelling active inference releases the next queued request")
    func activeCancellationReleasesNext() async throws {
        let scheduler = TranscriptionScheduler()
        let started = AsyncStream<Void>.makeStream()
        let log = SchedulerLog()
        let active = Task {
            try await scheduler.run(priority: .background) {
                started.continuation.yield()
                try await Task.sleep(for: .seconds(60))
            }
        }
        for await _ in started.stream { break }
        let next = Task {
            try await scheduler.run(priority: .manual) {
                await log.started("next")
                await log.finished("next")
            }
        }
        await Task.yield()

        active.cancel()

        await #expect(throws: CancellationError.self) { try await active.value }
        try await next.value
        #expect(await log.starts == ["next"])
        #expect(await log.maximumActive == 1)
    }
}

private actor SchedulerGate {
    private var entered = false
    private var openState = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered = true
        if openState { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func waitUntilEntered() async {
        while !entered { await Task.yield() }
    }

    func open() {
        openState = true
        let pending = continuations
        continuations.removeAll()
        for continuation in pending { continuation.resume() }
    }
}

private actor SchedulerLog {
    private(set) var starts: [String] = []
    private var active = 0
    private(set) var maximumActive = 0

    func started(_ value: String) {
        starts.append(value)
        active += 1
        maximumActive = max(maximumActive, active)
    }

    func finished(_ value: String) {
        active -= 1
    }
}
