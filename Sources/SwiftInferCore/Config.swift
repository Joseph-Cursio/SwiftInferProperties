/// Project-level configuration loaded from `.swiftinfer/config.toml`
/// per PRD v0.3 §5.8 (M2). The config layer carries knobs that the CLI
/// can override via flags; effective values are resolved at the CLI
/// layer with precedence CLI > config > defaults.
///
/// **Scope (M2 only).** Two knobs ship in M2.2:
///
/// - `includePossible`: default for the CLI's `--include-possible` flag.
///   PRD §4.2 hides Possible-tier suggestions by default; a project that
///   wants them on for everyone can flip the default here.
/// - `vocabularyPath`: optional override for the conventional
///   `.swiftinfer/vocabulary.json` location (PRD §4.5). Stored as the
///   raw TOML string; the CLI layer resolves relative paths against the
///   package root.
///
/// Tier thresholds are NOT configurable in M2 (M2 plan, open decision
/// #4) — they're PRD §4.2 constants. Adding cross-project comparability
/// later is easier than walking back project-specific calibrations.
///
/// Pure value type; no I/O. Loading from disk lives in `ConfigLoader`.
public struct Config: Sendable, Equatable {

    /// Default for the `discover --include-possible` flag. CLI flag wins
    /// when the user passes `--include-possible` or `--no-include-possible`
    /// explicitly; otherwise this value is used.
    public let includePossible: Bool

    /// Override for the conventional `.swiftinfer/vocabulary.json` path.
    /// Stored as the raw TOML string — the CLI layer resolves relative
    /// paths against the package root before handing them to
    /// `VocabularyLoader`.
    public let vocabularyPath: String?

    /// V1.32.C — Domain Template Packs (PRD §20.3). Comma-separated
    /// pack names that scope `discover` to a subset of the 5 shipped
    /// packs (numeric, serialization, collections, algebraic,
    /// concurrency). Example: `"numeric,serialization"`.
    ///
    /// Stored as the raw string so the same parser
    /// (`TemplatePack.parse(_:)`) handles both the CLI `--packs` flag
    /// and this config value uniformly. `nil` (default) means "all
    /// packs enabled" — the current monolithic-registry behavior.
    ///
    /// The MinimalTOMLParser doesn't support TOML arrays in v1; this
    /// string-encoded form is a pragmatic alternative consistent with
    /// the parser's existing scope. Future TOML-array support is a
    /// non-breaking upgrade (the array form would be additive).
    public let packs: String?

    public init(
        includePossible: Bool = false,
        vocabularyPath: String? = nil,
        packs: String? = nil
    ) {
        self.includePossible = includePossible
        self.vocabularyPath = vocabularyPath
        self.packs = packs
    }

    /// PRD-defined defaults: Possible tier hidden, no vocabulary
    /// override, all packs enabled. Used when no
    /// `.swiftinfer/config.toml` is present.
    public static let defaults = Config()
}
