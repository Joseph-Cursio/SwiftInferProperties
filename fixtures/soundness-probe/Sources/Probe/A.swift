public struct Meters: Equatable {
    public let value: Int
    public init(value: Int) { self.value = value }
    public func doubled() -> Meters { Meters(value: value * 2) }
}
