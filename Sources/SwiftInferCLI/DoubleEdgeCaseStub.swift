import Foundation

/// Shared curated real-axis `Double` edge-case set for the two-pass algebraic
/// verifier stubs (round-trip / idempotence / commutativity / associativity).
///
/// Prior to this the Double edge pass inlined a NaN-only generator (the
/// `Gen<Double>.doubleWithNaN()` equivalent) — a single curated entry. This
/// widens it to the full IEEE-754 real-axis edge set (±Infinity, ±0, the
/// overflow / underflow / subnormal boundaries) so a Double round-trip or
/// idempotence pick surfaces genuine ±Inf / signed-zero / overflow edge
/// advisories, not just NaN.
///
/// **Why engine-inline, not a kit generator.** The algebraic verifier workdir
/// pins `SwiftPropertyLaws` at `from: "2.1.0"` (resolves to the frozen 2.x
/// line, not kit `main` at 3.x), and the Double stub deliberately imports only
/// `Foundation` / `PropertyBased` / `RealModule` — no `PropertyLawComplex`. So
/// the curated set + generator are emitted inline here rather than delegated to
/// a `Gen<Double>.edgeCaseBiased()` the frozen verifier couldn't reach. This is
/// the single source of truth: the emitted generator, the emitted match
/// function, and the renderer's human labels all derive from `entries`, so they
/// can't drift.
///
/// **Index stability is an API contract** (mirroring the kit's
/// `complexEdgeCases`): `VERIFY_EDGE_INDEX` values are persisted into
/// `VerifyEvidence` and rendered by `VerifyResultRenderer`, so new entries
/// append to the end — existing indices never shift.
enum DoubleEdgeCaseStub {

    /// One curated real-axis IEEE-754 edge case.
    struct Entry {
        /// The Swift literal the generator emits for this case.
        let literal: String
        /// The human label the renderer shows in an edge-case advisory.
        let label: String
        /// A Bool expression over `value` recognizing this case. Needed because
        /// NaN and signed zero don't identify with a plain `==` (NaN compares
        /// unequal to everything; `-0.0 == 0.0` is `true`, so the sign must be
        /// checked explicitly).
        let match: String
    }

    /// Curated set. Order is the stable index contract — append only.
    static let entries: [Entry] = [
        Entry(literal: "Double.nan", label: "NaN", match: "value.isNaN"),
        Entry(literal: "Double.infinity", label: "+Infinity", match: "value == .infinity"),
        Entry(literal: "-Double.infinity", label: "-Infinity", match: "value == -.infinity"),
        Entry(literal: "0.0", label: "+0", match: "value == 0 && value.sign == .plus"),
        Entry(
            literal: "-0.0",
            label: "-0 (signed zero)",
            match: "value == 0 && value.sign == .minus"
        ),
        Entry(
            literal: "Double.greatestFiniteMagnitude",
            label: "greatestFiniteMagnitude",
            match: "value == .greatestFiniteMagnitude"
        ),
        Entry(
            literal: "-Double.greatestFiniteMagnitude",
            label: "-greatestFiniteMagnitude",
            match: "value == -.greatestFiniteMagnitude"
        ),
        Entry(
            literal: "Double.leastNonzeroMagnitude",
            label: "leastNonzeroMagnitude (subnormal)",
            match: "value == .leastNonzeroMagnitude"
        ),
        Entry(
            literal: "Double.leastNormalMagnitude",
            label: "leastNormalMagnitude",
            match: "value == .leastNormalMagnitude"
        )
    ]

    /// Human labels in index order — consumed by `VerifyResultRenderer`.
    static var labels: [String] { entries.map(\.label) }

    /// Curated entry count — the denominator in the renderer's
    /// "N / M curated edge cases sampled" line.
    static var curatedCount: Int { entries.count }

    /// The emitted `func matchEdgeCaseIndex(_ value: Double) -> Int` — returns
    /// the curated index of `value`, or `-1` for a non-curated (finite-slice)
    /// value. Column-0 based for direct interpolation into the stub's
    /// multiline literal.
    static var matchFunctionSource: String {
        var lines = ["func matchEdgeCaseIndex(_ value: Double) -> Int {"]
        for (index, entry) in entries.enumerated() {
            lines.append("    if \(entry.match) { return \(index) }")
        }
        lines.append("    return -1")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    /// The emitted edge generator. A single seeded `Gen<Int>.int` call drives a
    /// 90/10 bias: tags `0 ..< entries.count` map one-to-one onto the curated
    /// entries (each equally represented within the 10% slice), the rest fall
    /// through to a bounded-magnitude finite value — mirroring the kit's
    /// `Gen<Complex<Double>>.edgeCaseBiased()`.
    static var generatorSource: String {
        let edgeBound = entries.count * 10
        var lines = [
            "let edgeGenerator: Generator<Double, some SendableSequenceType> =",
            "    Gen<Int>.int(in: 0 ..< \(edgeBound)).map { tag -> Double in",
            "        switch tag {"
        ]
        for (index, entry) in entries.enumerated() {
            lines.append("        case \(index): return \(entry.literal)")
        }
        lines.append("        default: return Double.random(in: -1_000_000.0 ... 1_000_000.0)")
        lines.append("        }")
        lines.append("    }")
        return lines.joined(separator: "\n")
    }
}
