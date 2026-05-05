/// TestLifter M10.1 — one classified call site of the round-trip pair's
/// reverse-side function found inside a `SlicedTestBody`. The
/// `DomainCallSiteExtractor` (M10.1) produces these; the
/// `DomainInferrer` (M10.2) consumes them to decide whether the corpus's
/// reverse-side argument was uniformly the forward-side function's
/// output.
public struct DomainCallSite: Sendable, Equatable {

    /// How the first argument of the call site was classified — direct
    /// call to a producer, bare identifier (resolved against the slice's
    /// setup-region let-bindings by the M10.2 inferrer), or anything
    /// else (literal, closure, complex expression — treated as outlier
    /// per M10 plan §3.5 conservative bias).
    public let argument: ArgumentClassification

    public init(argument: ArgumentClassification) {
        self.argument = argument
    }
}

/// First-argument classification for a `DomainCallSite`. The three
/// cases cover the only argument shapes the M10.2 inferrer cares about:
/// direct producer-call output, identifier requiring let-binding
/// resolution, or anything else (treated as outlier and kills the
/// homogeneity check).
public enum ArgumentClassification: Sendable, Equatable {

    /// First argument is a direct call to `producerName(...)`. The
    /// producer's trailing identifier component matches `producerName` —
    /// `encode(t)`, `Codec.encode(t)`, and `someObj.encode(t)` all
    /// classify the same way (mirrors `AttributeScanner`'s trailing-
    /// component rule for `@Discoverable`).
    case callOutput(producerName: String)

    /// First argument is a bare identifier reference (e.g. `decode(x)`
    /// where `x` was bound in the surrounding scope). The M10.2 inferrer
    /// resolves these against the slice's setup-region `let x =
    /// forward(t)` bindings before applying homogeneity. An unresolved
    /// identifier post-resolution is treated as an outlier.
    case identifier(name: String)

    /// First argument is a literal, closure, complex expression, or
    /// anything else outside the two cases above. Treated as outlier
    /// per M10 plan §3.5 — one outlier kills the hint.
    case other
}
