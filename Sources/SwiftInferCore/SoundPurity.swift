import SwiftEffectInference
import SwiftSyntax

/// Soundly maps a function's purity onto SwiftEffectInference's `Effect`
/// lattice by taking the **meet of two independent refutations**:
///
/// - `ReducerPurityAnalyzer` refutes purity on TCA / concurrency effects
///   (`Effect` / `Task` / `await` / `.run` / `.send` / …) and hidden mutation
///   (static / `Self` writes).
/// - `SwiftEffectInference.PurityInferrer` refutes purity on I/O, logging,
///   nondeterminism, and partiality (totality — traps / force-unwraps).
///
/// `.pure` is claimed **only when neither refutes**. This is the crux of the
/// soundness argument (Idea #4, step 2): purity is *conjunctive* — a function
/// is `Effect.pure` only when none of the refuters fire — and each analyzer is
/// blind to the other's refuters. Mapping `ReducerPurity.pure` to `Effect.pure`
/// *alone* would be **unsound**, because `ReducerPurityAnalyzer` never inspects
/// I/O or totality: a reducer can be `ReducerPurity.pure` while still calling
/// `print()` or `Date()` or force-unwrapping. `Effect.pure` is the lattice
/// bottom and is *trusted* by every downstream consumer (a generated property
/// test runs a `.pure` function in-process and asserts a law over random
/// inputs), so a false `.pure` is the most dangerous claim the tool can make.
///
/// On the effect lattice a sound inference only ever over-approximates (never
/// claims an effect below the true one); when in doubt this returns `nil`
/// (refuted) rather than risk an unsound `.pure`.
///
/// ## A value, configured with one package's construction facts
///
/// SEI's `PurityInferrer` judges one declaration at a time, so `func make() -> Item { Item() }`
/// reads as pure while `Item` declares `let id = UUID()` in another file. SEI's
/// `ConstructionFacts` is the table that closes that: what constructing each of the package's
/// types runs. Its doc is explicit that **every** inferrer in a run gets the same table, because
/// one left at `.empty` silently disagrees with the configured ones.
///
/// That is why this is a value and not a namespace. Until 2026-10-06 it was an `enum` that built a
/// fresh unconfigured inferrer on every call — three call sites, each at `.empty` — so the table
/// had nowhere to go. Now one `PurityInferrer` is built in `init(constructionFacts:)` and every
/// answer below goes through it. The scanner gets one only from `PackagePurity`, which builds the
/// table from the package's production sources (`ConstructionUniverse`); there is deliberately no
/// default, and the unconfigured oracle is `internal`, so no production caller can opt out
/// without saying so. See `docs/measurements/construction-facts-wiring.md`.
public struct SoundPurity: Sendable {

    /// What constructing each of the package's types runs. Read-only: a `SoundPurity` is built
    /// from one table and keeps it, so two verdicts from one value cannot disagree about it.
    public let constructionFacts: ConstructionFacts

    /// The configured second refuter. One instance, not one per call: a `PurityInferrer` is an
    /// immutable value, and building it per call was how the table had nowhere to go.
    private let inferrer: PurityInferrer

    /// The oracle for one package: `constructionFacts` built once, from that package's
    /// production sources in a fixed order — `PackagePurity` is what does that.
    public init(constructionFacts: ConstructionFacts) {
        self.constructionFacts = constructionFacts
        self.inferrer = PurityInferrer(constructionFacts: constructionFacts)
    }

    /// No construction facts — the oracle exactly as it answered before the table existed.
    ///
    /// **`internal`, and that is the guard.** A public `.unconfigured` would be the silent
    /// `.empty` default SEI warns about, spelled differently. Tests reach it through
    /// `@testable import`; no production file names it (`PurityConfigurationInventoryTests`).
    static let unconfigured = Self(constructionFacts: .empty)

    /// Returns `.pure` iff **both** analyzers agree the function is pure;
    /// otherwise `nil` (purity refuted — the caller must not emit a `pure`
    /// claim, e.g. a `/// @lint.effect pure` suggestion).
    public func inferredEffect(for function: FunctionDeclSyntax) -> Effect? {
        // First refuter: TCA effects / hidden mutation. Cheap, and the common
        // reason a reducer is not pure.
        guard ReducerPurityAnalyzer.analyze(function) == .pure else { return nil }
        // Second refuter: I/O / nondeterminism / partiality. Catches exactly
        // what ReducerPurity is blind to — this is what makes the mapping sound.
        return inferrer.inferredEffect(for: function)
    }

    /// Convenience boolean form of `inferredEffect(for:)`.
    public func isPure(_ function: FunctionDeclSyntax) -> Bool {
        inferredEffect(for: function) == .pure
    }

    /// The full three-state verdict, kept sound the same way `inferredEffect`
    /// is: `ReducerPurityAnalyzer` refutes first, and only then does the
    /// syntactic inferrer get to distinguish partial from refuted.
    ///
    /// **What is in the `.refuted` third is measured, and a third of it is not
    /// evidence.** Re-taken 2026-10-06 over `Sources/`, with construction facts:
    /// 341 refutations of 3,217 functions, of which **223 carry a witness and 118
    /// name nothing in the source at all** — a `throws` whose `try` reaches a
    /// callee this leaf cannot resolve. (First taken 2026-08-17: 152 of 284, the
    /// majority. The construction table moved 2 rows out of that half, re-witnessed
    /// as constructions, and flipped no verdict.)
    /// `docs/measurements/purity-refuted-bucket-census.md` has the split, and
    /// one thing a caller reading this should know before counting it: the
    /// *"could not be inspected at all"* half of `PurityVerdict.refuted`'s own
    /// doc is **unreachable** through `FunctionScanner`, which skips protocol
    /// bodies — so every refutation here has a callee to name. (The census also
    /// found 180 computed-property summaries reaching `.refuted` by an
    /// initialiser default; that is fixed below, in `verdict(forGetter:)`.)
    ///
    /// **Nothing consumes `.pureButPartial` yet, and that is deliberate.**
    /// Measured on this repo 2026-08-04: of 2,500 functions, 2,206 are `.pure`,
    /// **35 are `.pureButPartial`**, 259 refuted (re-taken 2026-10-06: 2,839 / 37 /
    /// 341 of 3,217). The single consumer of the
    /// purity signal is the `/// @lint.effect pure` advisory, and a partial
    /// function cannot honestly take that annotation — SEI defines the tier as
    /// "no side effects, deterministic, **and total**", and the lattice has no
    /// tier for deterministic-but-partial. Advising those 35 anything today
    /// would mean inventing a claim or telling 35 functions something false.
    ///
    /// So this exists to stop the distinction being **discarded at the scan
    /// boundary**, which is where it was being lost: `isPure` collapses three
    /// states to two and the third is unrecoverable downstream. A consumer that
    /// can narrow a law's domain to the non-throwing inputs — which is exactly
    /// what `PurityVerdict`'s own doc says the method is for — now has
    /// something to read.
    ///
    /// The soundness argument is unchanged and worth restating, because
    /// admitting `throws` sounds like relaxing the gate this project warns
    /// about ("removing the `throws` gate once re-admitted `Process`/`Pipe`/
    /// `FileHandle`/SQLite at once"). It is not: `.pureButPartial` requires the
    /// body contain **no `try` at all**, so a throw propagated from a dependency
    /// still refutes. Only a function raising its own errors qualifies.
    public func verdict(for function: FunctionDeclSyntax) -> PurityVerdict {
        guard ReducerPurityAnalyzer.analyze(function) == .pure else { return .refuted }
        return inferrer.verdict(for: function)
    }

    /// The same verdict for a **read-only computed property's getter**, which
    /// the templates model as a nullary `self -> T` map.
    ///
    /// This exists because the scan had no oracle for that shape and answered
    /// with a constant. `makeSummary(fromComputedProperty:)` passed
    /// `isInferredPure: true` unconditionally and no `purityVerdict` at all, so
    /// every computed property simultaneously claimed purity and took
    /// `FunctionSummary.init`'s `.refuted` default — the one combination that
    /// field's own doc says cannot occur. Measured 2026-08-17: 180 of them under
    /// `Sources/`, which is **39% of the `.refuted` bucket a consumer reads**,
    /// none of it a verdict. See `docs/measurements/purity-refuted-bucket-census.md`.
    ///
    /// **The meet is taken here for the same reason it is taken above**, not as
    /// belt-and-braces: `PurityInferrer.isPure(_ accessor:)` answers the effect
    /// question — markers and totality — and says so in its own doc, while
    /// `ReducerPurityAnalyzer` owns the TCA/concurrency surface and static
    /// writes. A getter can return a `Task` or write to `Self.cache` as readily
    /// as a function can. Claiming `.pure` on one refuter is the lattice-bottom
    /// mistake, whichever shape it is claimed about.
    ///
    /// **Never `.pureButPartial`, and the reason is a filter rather than a
    /// property.** `isReadOnlyGetter` rejects `async` and `throws` accessors
    /// before this is reached, so no partial getter arrives; SEI's accessor
    /// oracle is a `Bool` and offers no third state anyway. If that filter is
    /// ever widened to admit a throwing getter, this method — not the filter —
    /// is what has to learn the distinction, or the partial case will silently
    /// read as fully pure.
    ///
    /// **A/B when this replaced the constant: 0 advisory rows moved.** Neither
    /// refuter fires on any of the 180 (measured separately, both at zero), so
    /// the unchecked `true` had been accidentally correct on this corpus the
    /// whole time. That is the measurement that keeps this a repair of an
    /// unasked question rather than a bug fix with a victim — and it is exactly
    /// why the shape it admits (`var now: Date { Date() }`, advised `pure`) is
    /// pinned by a test rather than left to the next corpus to discover.
    public func verdict(forGetter accessor: AccessorBlockSyntax) -> PurityVerdict {
        guard ReducerPurityAnalyzer.analyze(Self.getterOnly(of: accessor)) == .pure else { return .refuted }
        return inferrer.isPure(accessor) ? .pure : .refuted
    }

    /// SEI's first witness for `function` under this value's facts — `refutation(for:)` on the
    /// same configured inferrer `verdict(for:)` asks, so the two cannot disagree about the table.
    ///
    /// The SEI half only: `ReducerPurityAnalyzer` names no witness, so a function it refutes can
    /// still answer `nil` here. `nil` otherwise means SEI did not refute (`.pure`, or a
    /// `.pureButPartial` raising only its own errors).
    public func inferrerRefutation(for function: FunctionDeclSyntax) -> PurityRefutation? {
        inferrer.refutation(for: function)
    }

    /// The getter's statements, not the whole accessor block.
    ///
    /// **Open item 50's second half, and it is INERT today — measured, not assumed.**
    /// `ReducerPurityAnalyzer` walks whatever syntax it is handed, so passing the block
    /// let it read a `_read` or `unsafeAddress` body it was never asked about: a `get`
    /// returning `1` beside a `_read` writing `S.cache` measured `hiddenMutability`, which
    /// is a true statement about the property and a false one about its getter.
    ///
    /// **It changes no verdict, because SEI's rule dominates.**
    /// `PurityInferrer.isPure(_ accessor:)` returns `false` on the *presence* of any
    /// non-`get` accessor — it never reads that accessor's body — so the meet is
    /// `.refuted` either way. The narrowing matters only if SEI relaxes that rule, and
    /// `narrowingIsInertWhileSEIRefusesNonGetAccessors` says so in a test rather than
    /// leaving the next reader to rediscover it.
    ///
    /// Kept anyway, on item 40's precedent: a correct oracle pointed at the right node,
    /// closing a latent misreading at zero measured cost.
    static func getterOnly(of accessor: AccessorBlockSyntax) -> Syntax {
        switch accessor.accessors {
        case let .getter(statements):
            // The shorthand `var x: T { … }` — the body IS the getter.
            return Syntax(statements)

        case let .accessors(list):
            guard let getter = list.first(where: { $0.accessorSpecifier.tokenKind == .keyword(.get) }),
                  let body = getter.body else {
                // No getter to isolate. Hand back the block unchanged rather than an empty
                // node: an empty one reads as *nothing impure here*, which is the
                // permissive direction and the one this file exists to avoid.
                return Syntax(accessor)
            }
            return Syntax(body.statements)
        }
    }
}
