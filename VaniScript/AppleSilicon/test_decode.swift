import Foundation
import VaniScriptCore

let json = """
{"currentChunkDurationSec":248.08,"phase":"transcribing"}
"""
let decoder = JSONDecoder()
do {
    let obj = try decoder.decode(BatchProgressDetail.self, from: Data(json.utf8))
    print("Success: \(obj)")
} catch {
    print("Failed: \(error)")
}
