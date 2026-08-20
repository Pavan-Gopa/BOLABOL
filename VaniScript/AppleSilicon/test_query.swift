import Foundation
@testable import VaniScriptRuntime
import VaniScriptCore

func test() async throws {
    let url = URL(fileURLWithPath: "/Users/pavan/Library/Application Support/VaniScript/Batch/jobs.sqlite")
    let repo = try SQLiteBatchJobRepository(url: url)
    let jobs = try await repo.list()
    for job in jobs.prefix(3) {
        print(job.state, job.progressDetail != nil)
    }
}
Task {
    do { try await test() } catch { print(error) }
    exit(0)
}
RunLoop.main.run()
