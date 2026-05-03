/// Lightweight matching key for TestLifter ↔ TemplateEngine
/// cross-validation per PRD §4.1's +20 signal. Uses only what TestLifter
/// can extract from a test body — the template name + the sorted
/// callee-name tuple for the function (or function pair) the lifted
/// property closes over.
///
/// **Why not the full `SuggestionIdentity`?** PRD §7.5 specifies the
/// identity hash as `(template ID, function signature canonical form,
/// AST shape of property region)`. The "function signature canonical
/// form" includes parameter and return *types* — information TestLifter
/// can't recover from call sites without semantic resolution beyond
/// SwiftSyntax. The TestLifter M1 plan's open decision #4 default
/// `(a)` resolves this with a "canonicalized-prefix match" — the
/// `CrossValidationKey` is that prefix made concrete: template name +
/// sorted callee names, nothing type-dependent.
///
/// **Sorted callee names:** for symmetric-pair templates (round-trip)
/// the orientation `[encode, decode]` and `[decode, encode]` both
/// hash to the same key. For unary templates (idempotence,
/// monotonicity, etc.) the array has one element.
public struct CrossValidationKey: Sendable, Hashable {

    public let templateName: String

    /// Sorted lexicographically at construction so two keys built from
    /// the same callee set hash identically regardless of which side
    /// the producer treated as "forward."
    public let calleeNames: [String]

    public init(templateName: String, calleeNames: [String]) {
        self.templateName = templateName
        self.calleeNames = calleeNames.sorted()
    }
}
