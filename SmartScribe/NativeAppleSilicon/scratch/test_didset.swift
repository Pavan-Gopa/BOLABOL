import Foundation
import Combine

class TestStore: ObservableObject {
    @Published var notes: [String] = [] {
        didSet {
            print("--- didSet notes called! Count = \(notes.count)")
        }
    }
    @Published var selection: String? = nil {
        didSet {
            print("--- didSet selection called! Value = \(String(describing: selection))")
        }
    }
}

let store = TestStore()
print("1. Modifying notes array by inserting...")
store.notes.insert("Hello", at: 0)
print("2. Modifying selection...")
store.selection = "Hello"
