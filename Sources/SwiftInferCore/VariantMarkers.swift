/// Name markers that say "this function is a **second implementation** of one
/// next to it" — the vocabulary behind the differential / oracle family.
///
/// ## The law this serves
///
/// Two implementations of one specification must agree. A codebase that ships
/// a fast path next to a reference path has written down a property and then
/// not tested it:
///
/// ```swift
/// Parser.parse(source:)                          // the reference
/// Parser.parseIncrementally(source:parseTransition:)   // the fast path
/// ```
///
/// swift-syntax states the law in its own test utilities
/// (`IncrementalParseTestUtils.swift:26`): *"verify that incrementally parsing
/// the edited source based on the original source produces the same syntax
/// tree as reparsing the post-edit file from scratch."* It is a property —
/// quantified over every edit — written as an example harness.
///
/// This is the family `docs/parsing-catalog-gap.md` §6 names, and it has two
/// independent witnesses: the incremental parser above, and the TestLifter
/// finding that `mySort(x) == x.sorted()` in a hand-rolled random test is
/// invisible because no template claims that shape.
///
/// ## Reach, measured before building
///
/// Across ~5,900 distinct function names in seven corpora (swift-syntax,
/// swift-collections, swift-nio, swift-argument-parser,
/// swift-async-algorithms, SwiftProjectLint, this repo) the marker vocabulary
/// below matches **12 pairs** — 0.2%. That is thin, and it is stated here so
/// nobody has to rediscover it: this family is high-value-per-firing and
/// low-frequency, which is the precision-over-recall posture PRD §3.5 asks
/// for, not an accident.
///
/// All four marker forms are exercised by real code, which is why each is in
/// the list rather than guessed:
///
/// | marker | form | measured on |
/// |---|---|---|
/// | `Incrementally` | suffix | `parse` / `parseIncrementally` (swift-syntax) |
/// | `Slow` | suffix | `_ensureFreeCapacity` / `_ensureFreeCapacitySlow` (swift-collections) |
/// | `Fallback` | suffix | `_addHTTPClientHandlers` / `…Fallback` (swift-nio) |
/// | `unchecked` | prefix | 9 pairs on swift-collections (`append` / `uncheckedAppend`, …) |
///
/// ## Which side is the reference
///
/// The **unmarked** name. `parse` is the specification; `parseIncrementally`
/// is the optimisation that must match it. That direction matters for the
/// emitted law and for the caveat: a divergence is a bug in the *variant*,
/// not in the reference.
public enum VariantMarkers {

    /// Markers written as a **suffix** on the reference's stem —
    /// `parse` → `parseIncrementally`.
    ///
    /// `Incremental`/`Incrementally` both listed because Swift naming takes
    /// either; a missing spelling fails silently, which is the failure mode
    /// this catalog keeps relearning.
    public static let suffixMarkers: [String] = [
        "Incrementally", "Incremental",
        "Fast", "FastPath", "Slow", "SlowPath",
        "Naive", "Optimized", "Optimised",
        "Reference", "BruteForce", "Fallback", "Unoptimized"
    ]

    /// Markers written as a **prefix** — `append` → `uncheckedAppend`.
    ///
    /// Spelled lowercase-first because that is how they appear at the head of
    /// a Swift method name.
    public static let prefixMarkers: [String] = [
        "unchecked", "unsafe", "fast", "slow", "naive",
        "optimized", "optimised", "bruteForce", "reference"
    ]

    /// Markers whose variant **elides a precondition** rather than optimising
    /// a computation. Their law is *conditional*: the two agree only where the
    /// precondition holds, and a generator that violates it will trap — a trap
    /// that is NOT a refutation.
    ///
    /// Kept separate so the emitted caveat can say which kind of variant this
    /// is instead of issuing one vague warning for both.
    public static let preconditionElidingMarkers: Set<String> = ["unchecked", "unsafe"]

    /// A recognised reference/variant name pair.
    public struct VariantPair: Sendable, Equatable {
        /// The unmarked name — the specification.
        public let reference: String
        /// The marked name — the implementation that must match it.
        public let variant: String
        /// The marker that related them, as written.
        public let marker: String
        /// Whether the variant merely drops a precondition, making the law
        /// conditional on that precondition holding.
        public let elidesPrecondition: Bool

        public init(reference: String, variant: String, marker: String, elidesPrecondition: Bool) {
            self.reference = reference
            self.variant = variant
            self.marker = marker
            self.elidesPrecondition = elidesPrecondition
        }
    }

    /// Whether `variant` is `reference` plus a variant marker, and if so which.
    ///
    /// Order-insensitive at the call site: try both orderings and take the one
    /// that answers, because the caller does not know in advance which of two
    /// names is the marked one.
    public static func relate(reference: String, variant: String) -> VariantPair? {
        guard reference != variant else { return nil }
        for marker in suffixMarkers where variant == reference + marker {
            return VariantPair(
                reference: reference, variant: variant, marker: marker,
                elidesPrecondition: preconditionElidingMarkers.contains(marker.lowercased())
            )
        }
        // Prefix form: `append` → `uncheckedAppend`. The reference's first
        // character is upper-cased when it follows the marker.
        guard let head = reference.first else { return nil }
        let capitalised = head.uppercased() + reference.dropFirst()
        for marker in prefixMarkers where variant == marker + capitalised {
            return VariantPair(
                reference: reference, variant: variant, marker: marker,
                elidesPrecondition: preconditionElidingMarkers.contains(marker.lowercased())
            )
        }
        return nil
    }

    /// `relate` tried in both directions — returns the pair with `reference`
    /// correctly identified as the unmarked half, whichever way round the two
    /// names arrived.
    public static func relateEitherOrder(_ lhs: String, _ rhs: String) -> VariantPair? {
        relate(reference: lhs, variant: rhs) ?? relate(reference: rhs, variant: lhs)
    }
}
