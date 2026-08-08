/// A path segment.
public struct PathSegment: Equatable {

    public var text: String

    public init(text: String) {
        self.text = text
    }

    /// Combine this segment with another, separated by `/`.
    public func combine(_ other: PathSegment) -> PathSegment {
        PathSegment(text: text + "/" + other.text)
    }
}
