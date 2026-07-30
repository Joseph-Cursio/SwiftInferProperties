import Foundation

/// The `(file basename, bare symbol)` key that joins a **seed manifest** to a
/// **scanned function**.
///
/// Basename rather than full path because the two sides spell paths differently: a
/// linter emits what it was invoked with (often relative), the scanner emits an
/// absolute URL. Bare symbol rather than the labelled display name for the same
/// reason — producers disagree about whether to write `extractValue` or
/// `extractValue(from:)`.
///
/// **Extracted to Core because two modules now key on it.** `SwiftInferCLI` uses it
/// to decide which seeds a run may synthesize a generic law for; `SwiftInferTemplates`
/// uses it to decide which access-restricted functions a seed has rescued into the
/// template pipeline. Those two must agree exactly — a seed that reads as "rescued"
/// on one side and "not rescued" on the other produces a function that is analysed
/// but never surfaced, or surfaced with the wrong caveat. Duplicating a two-line
/// string formula across module boundaries is precisely how that drifts, and there is
/// no compiler check that would catch it.
///
/// The key is deliberately *lossy*: two same-named functions in same-named files in
/// different targets collide. `Discover+Seeds` documents that collision and the
/// measurement behind it (145 seeds, 134 keys, no key spanning two files on
/// SwiftProjectLint) — it is a known, currently-empty hazard, not an oversight.
public enum SymbolJoinKey {

    /// `("/abs/path/Visitors.swift", "extractStringValue")` → `"Visitors.swift::extractStringValue"`.
    public static func make(file: String, symbol: String) -> String {
        "\(URL(fileURLWithPath: file).lastPathComponent)::\(symbol)"
    }

    /// The key for a scanned function, from its own location and name.
    public static func make(for summary: FunctionSummary) -> String {
        make(file: summary.location.file, symbol: summary.name)
    }
}
