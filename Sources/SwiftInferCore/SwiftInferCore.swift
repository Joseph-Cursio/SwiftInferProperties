/// SwiftInferCore — shared data model for type-directed property inference.
///
/// Holds the records the rest of the package operates on: function summaries
/// (`FunctionSummary`), template suggestions (`Suggestion`, `Score`,
/// `ExplainabilityBlock`), the suggestion-identity hash
/// (`SuggestionIdentity`), the `// swiftinfer: skip` marker scanner
/// (`SkipMarkerScanner`), and the `Vocabulary` schema. The full scope
/// is documented in `docs/SwiftInferProperties PRD v0.4.md`.
///
/// The module intentionally exposes no top-level enum / struct / class
/// named `SwiftInferCore` — that name collision shadowed the module
/// name in downstream consumers (TestLifter M1.1) and blocked
/// `SwiftInferCore.SourceLocation` from resolving to the module's
/// `SourceLocation` struct. Resolved here by leaving the file as a
/// documentation-only marker.
