/// A running summary of a series of values.
///
/// Combining accumulates both series.
public struct SumSummary: Equatable {

    public var total: Int
    public var count: Int

    public init(total: Int, count: Int) {
        self.total = total
        self.count = count
    }

    /// The mean this summary represents.
    public var mean: Double {
        count == 0 ? 0 : Double(total) / Double(count)
    }

    /// Combine this summary with another.
    ///
    /// Wrapping addition keeps the operation total: an overflow trap would be
    /// recorded as an error rather than as a verdict.
    public func combine(_ other: SumSummary) -> SumSummary {
        SumSummary(total: total &+ other.total, count: count &+ other.count)
    }
}

/// A running summary that blends two series rather than accumulating them.
public struct BlendSummary: Equatable {

    public var total: Int
    public var count: Int

    public init(total: Int, count: Int) {
        self.total = total
        self.count = count
    }

    /// The mean this summary represents.
    public var mean: Double {
        count == 0 ? 0 : Double(total) / Double(count)
    }

    /// Combine this summary with another, blending their totals.
    public func combine(_ other: BlendSummary) -> BlendSummary {
        BlendSummary(total: (total &+ other.total) / 2, count: Swift.max(count, other.count))
    }
}
