/// SwiftInferCore — shared data model for type-directed property inference.
///
/// Holds the records the rest of the package operates on: function summaries
/// produced by the SwiftSyntax pipeline (M1.2), template suggestions
/// (`Suggestion`, `Score`, `ExplainabilityBlock` — landing M1.3), and the
/// `// swiftinfer: skip` marker representation (M1.5).
///
/// The full milestone breakdown lives in `docs/M1 Plan.md`; the product
/// specification is `docs/SwiftInferProperties PRD v0.3.md`.
public enum SwiftInferCore {
    /// Marker for the unreleased pre-M1 scaffold. Removed once
    /// Contribution 1 (TemplateEngine) lands a usable surface.
    public static let version = "0.0.0-scaffold"
}
