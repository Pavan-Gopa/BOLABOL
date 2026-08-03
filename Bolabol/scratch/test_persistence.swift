import Foundation
import NativeBolabolCore

@MainActor
func test() {
    let fileManager = FileManager.default
    let tempURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    print("Temp URL: \(tempURL.path)")
    defer {
        try? fileManager.removeItem(at: tempURL)
    }

    let store1 = NoteStore(notes: [], fileManager: fileManager, notesFileURL: tempURL, isPersistenceEnabled: true)
    let note = store1.addEmptyNote(title: "Persistent Note")
    print("Added note: \(note.title), id: \(note.id)")
    
    // Check if file exists and print contents
    if fileManager.fileExists(atPath: tempURL.path) {
        print("File exists! Size: \(try! fileManager.attributesOfItem(atPath: tempURL.path)[.size]!)")
        if let content = try? String(contentsOf: tempURL) {
            print("Contents: \(content)")
        }
    } else {
        print("File does NOT exist on disk after addEmptyNote!")
    }

    let store3 = NoteStore(notes: nil, fileManager: fileManager, notesFileURL: tempURL, isPersistenceEnabled: true)
    print("Store3 loaded notes count: \(store3.notes.count)")
    if let firstNote = store3.notes.first {
        print("First note title: \(firstNote.title)")
    }
}

test()
