/// The stored state an instance method writes and removes from, recorded for every non-static method in
/// a type so the uniquifier template can read a function's siblings (#692, condition 1).
///
/// A sibling that writes the state a uniquifier tests, and is not itself a uniquifier, is a setup call:
/// SwiftUMLStudio's `reserveIdentifiers(drawing:)` fills `takenIdentifiers` before `uniqName` issues
/// anything, and without it the plain law is false on correct code. A sibling that removes from it hands
/// released names out again.
public struct StateWrites: Sendable, Equatable {
    /// Stored names the body appends to, inserts into, assigns or increments, `self.` removed.
    public let written: Set<String>
    /// Stored names the body removes from: `remove…`, `subtract`, `popFirst`, or `t[k] = nil`.
    public let removed: Set<String>

    /// Creates the record.
    public init(written: Set<String>, removed: Set<String>) {
        self.written = written
        self.removed = removed
    }

    /// Writes nothing and removes nothing.
    public static let empty = Self(written: [], removed: [])
}
