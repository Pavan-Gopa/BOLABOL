import Foundation

public struct FocusedTextInsertionSnapshot: Equatable, Sendable {
    public var value: String
    public var selection: NSRange

    public init(value: String, selection: NSRange) {
        self.value = value
        self.selection = selection
    }

    public func inserting(_ text: String) -> FocusedTextInsertionSnapshot {
        let nsValue = value as NSString
        let boundedLocation = min(max(0, selection.location), nsValue.length)
        let boundedLength = min(max(0, selection.length), nsValue.length - boundedLocation)
        let boundedRange = NSRange(location: boundedLocation, length: boundedLength)
        let updatedValue = nsValue.replacingCharacters(in: boundedRange, with: text)
        let updatedSelection = NSRange(location: boundedLocation + (text as NSString).length, length: 0)
        return FocusedTextInsertionSnapshot(value: updatedValue, selection: updatedSelection)
    }
}
