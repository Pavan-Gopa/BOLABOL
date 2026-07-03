import Foundation
import NativeSmartScribeCore
import Testing

@Test
func focusedTextInsertionReplacesSelectedRange() {
    let snapshot = FocusedTextInsertionSnapshot(
        value: "Hello brave world",
        selection: NSRange(location: 6, length: 6)
    )

    let result = snapshot.inserting("smart ")

    #expect(result.value == "Hello smart world")
    #expect(result.selection.location == 12)
    #expect(result.selection.length == 0)
}

@Test
func focusedTextInsertionAppendsWhenSelectionIsOutOfBounds() {
    let snapshot = FocusedTextInsertionSnapshot(
        value: "Hello",
        selection: NSRange(location: 99, length: 4)
    )

    let result = snapshot.inserting(" world")

    #expect(result.value == "Hello world")
    #expect(result.selection.location == 11)
    #expect(result.selection.length == 0)
}
