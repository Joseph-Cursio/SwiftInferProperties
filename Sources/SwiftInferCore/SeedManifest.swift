import Foundation

/// A property-test *seed manifest* produced by an external linter and consumed
/// by `swift-infer discover --seeds`.
///
/// SwiftProjectLint's `--format pbt-seeds` emits this document: each seed names
/// a function the linter judged a good property-based-test candidate (pure,
/// total, takes inputs, returns a value). `discover --seeds` uses it to *focus*
/// inference output on exactly those functions — the keystone of the
/// lint → infer → verify pipeline.
///
/// The schema mirrors the producer's:
/// ```json
/// { "version": 2, "seeds": [ { "file": "Math.swift", "line": 3, "symbol": "add",
///                              "rule": "Pure Function …", "kind": "pure-function",
///                              "role": "predicate" } ] }
/// ```
/// `role`, `restriction` and `effect` are decoded leniently (optional) because absence is a
/// *meaningful* answer for each: the producer classifies roles on three of its four seeding rules,
/// restrictions on `restricted-function` seeds, and effects on `idempotency` seeds, so a seed
/// without one is a seed nobody asked the question about.
///
/// `file`/`line`/`symbol`/`rule`/`kind` are required. The first three locate the seed, `kind`
/// decides whether this tool may narrow discovery onto it — a question with no safe default — and
/// `rule` is required because **the producer always emits it** (`PBTSeed.rule` is a non-optional
/// `String`, written from `issue.ruleName.rawValue` on every seed), so absence means a malformed or
/// hand-edited manifest rather than an honest unknown. Measured 2026-08-06 over this repo's own
/// sources: 0 of 2,099 seeds lacked it.
///
/// It was `String?` until then, and lenient decoding was not the real cost — **nothing read it at
/// all**. The field was write-only for the whole of its life, while this repo's warnings said
/// "this is a LINTER gap" without naming a rule and reported an unreadable `kind` without saying
/// which rule produced it.
public struct SeedManifest: Codable, Sendable, Equatable {

    /// The schema version this build understands. A manifest with a different
    /// version is still consumed best-effort, but the CLI warns.
    ///
    /// **v2 added `kind`** — see `SeedKind`. The field is what distinguishes a seed naming a
    /// function to *analyse* from one naming a place where a human must *refactor first*.
    public static let supportedVersion = 2

    public let version: Int
    public let seeds: [Seed]

    public init(version: Int = Self.supportedVersion, seeds: [Seed]) {
        self.version = version
        self.seeds = seeds
    }

    /// Seeds this tool may narrow discovery to.
    public var analysableSeeds: [Seed] {
        seeds.filter(\.kind.isAnalysable)
    }

    /// Seeds naming work a human must do before any tool can help — pure logic that exists but has
    /// no name yet.
    public var refactorPendingSeeds: [Seed] {
        seeds.filter { !$0.kind.isAnalysable }
    }

    /// One seeded location: enough to find it, and — via `kind` — enough to know what may be done
    /// with it.
    public struct Seed: Codable, Sendable, Equatable {
        public let file: String
        public let line: Int
        public let symbol: String

        /// The linter rule that produced this seed, for attribution.
        ///
        /// Required — see the type doc. Not a focus key and never matched on: two rules can seed the
        /// same symbol, and the *remedy* differs by rule while the location does not.
        public let rule: String
        public let kind: SeedKind

        /// What the logic **is**, when the linter classified it. `nil` from any producer that does
        /// not emit roles — which is every producer before this field existed.
        public let role: SeedRole?

        /// **What would have to move** for a test to reach this symbol — see `SeedRestriction`.
        ///
        /// Only `restricted-function` seeds carry one. It is the part of the access answer this side
        /// structurally cannot compute: `FunctionScanner`'s enclosing-type stack is
        /// same-declaration only, so a member of an unmarked `extension` of a `private` type reads
        /// locally as blocked by its own modifier, and the widening remedy derived from that is a
        /// no-op.
        public let restriction: SeedRestriction?

        /// Where the linter placed this symbol on the effect lattice — what it
        /// claimed, what its body reached, and how the linter knows.
        ///
        /// Only idempotency seeds carry one. `nil` from any producer that does
        /// not emit tiers, which is every producer before the field existed —
        /// and, importantly, still the honest reading for a seed about purity
        /// rather than retry-safety.
        public let effect: SeedEffect?

        /// `rule` carries a default here and is **required by the decoder**, mirroring `kind`.
        ///
        /// The two initialisers answer different questions. This one is construction — mostly
        /// tests, which have no rule to name and no interest in one. `init(from:)` is *reading a
        /// producer's document*, where a missing field means the document is wrong.
        public init(
            file: String,
            line: Int,
            symbol: String,
            rule: String = "(unattributed)",
            kind: SeedKind = .pureFunction,
            role: SeedRole? = nil,
            restriction: SeedRestriction? = nil,
            effect: SeedEffect? = nil
        ) {
            self.file = file
            self.line = line
            self.symbol = symbol
            self.rule = rule
            self.kind = kind
            self.role = role
            self.restriction = restriction
            self.effect = effect
        }

        /// `kind` is **required**, and that is a deliberate reversal.
        ///
        /// It used to default to `.pureFunction` so a v1 manifest — written before `kind` existed —
        /// still decoded. No v1 manifest can exist any more: the producer's version is a constant
        /// 2, and manifests are generated on demand rather than archived (SwiftProjectLint
        /// gitignores its own). The tolerance outlived the thing it tolerated.
        ///
        /// Keeping it was worse than useless, because it is a **silent** default on the one field
        /// whose misreading the v1 → v2 bump was created to prevent. A producer that ever drops or
        /// misspells `kind` through a bug would have every seed read as `.pureFunction` —
        /// *analysable* — and discovery would narrow onto uncallable kernels and report a confident
        /// zero. That is the exact failure described in `SeedKind`, arriving through the hatch
        /// installed to stop it. Required turns it into a loud parse error naming the file.
        ///
        /// The version *number* check is untouched and still earns its keep: it is forward
        /// compatibility, for a future v3 producer meeting this build.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: SeedField.self)
            self.file = try container.decode(String.self, forKey: .file)
            self.line = try container.decode(Int.self, forKey: .line)
            self.symbol = try container.decode(String.self, forKey: .symbol)
            // Required since 2026-08-06. The producer's own field is non-optional and every one of
            // 2,099 measured seeds carried it, so a manifest without it is malformed rather than
            // reticent — and the lenient reading bought nothing, since nothing consumed the field.
            self.rule = try container.decode(String.self, forKey: .rule)
            self.kind = try container.decode(SeedKind.self, forKey: .kind)
            // Unlike `kind`, absence needs no semantic default: a seed with no role is a seed whose
            // producer classifies nothing, and "unknown" is the honest reading.
            self.role = try container.decodeIfPresent(SeedRole.self, forKey: .role)
            // Same reading as `role`: only `restricted-function` seeds are classified, so absent is
            // "not asked" rather than a value to guess. Guessing `.declaration` would be the worst
            // available default — it is the one that licenses a widening patch.
            self.restriction = try container.decodeIfPresent(SeedRestriction.self, forKey: .restriction)
            // Same reading as `role`: a seed with no effect is one whose producer
            // resolves no lattice position for it, and absent is honest.
            self.effect = try container.decodeIfPresent(SeedEffect.self, forKey: .effect)
        }
    }
}

/// What a seed *is*, which decides what may be done with it.
///
/// A seed is not always a symbol to analyse. Some name a place where pure logic **exists but has no
/// name yet** — an extractable kernel inlined in an impure method. There is nothing to index there:
/// nothing to call, nothing to generate inputs for, no signature to satisfy. The symbol names the
/// *enclosing* function, which is a **location**, not a subject.
///
/// **Narrowing discovery to such a seed produces a confident zero.** Focus on
/// `uploadRemainingChunks` and this tool must refuse it — `private async throws` refutes purity —
/// and then report `kept 0` for a codebase that demonstrably has property-testable logic in it. That
/// is the exact failure the empty-manifest guard exists to prevent, arriving by a new route: a tool
/// telling the reader "there is nothing here" when there is. So a non-analysable seed is *reported*
/// to the reader as work to do, and never focused on.
public enum SeedKind: Sendable, Equatable {
    /// A pure, total function. Index it, propose laws, run them.
    case pureFunction

    /// A function claiming idempotence that calls non-idempotent work — it arrives with a
    /// ready-made property.
    case idempotency

    /// Pure logic trapped inside an impure method. Real, valuable, **not yet callable**.
    case extractableKernel

    /// A pure, total, **named** function that no test can reach: `private` or `fileprivate`, or
    /// nested inside a type that is.
    ///
    /// This tool already knew about these — `RestrictedFunction` sets them aside, on the grounds
    /// that `@testable import` raises `internal` and stops there. What it could not know was that
    /// the linter was *seeding them as analysable*: 316 of 468 supposedly actionable seeds named a
    /// function no test could call. The two tools had been disagreeing silently, and only noticed
    /// once both sides stated their beliefs in a comparable vocabulary.
    ///
    /// **Analysable — the kind is a label, not a gate.**
    ///
    /// It first shipped grouped with `extractableKernel` as not-analysable, which conflated two
    /// different obstacles. A kernel has no symbol: nothing to call, no signature, no law to
    /// propose. A restricted function has both, and lacks only *verifiability* from another module.
    /// `isAnalysable` asks whether analysis may be narrowed to this symbol, and for a private
    /// function the answer is yes.
    ///
    /// Getting that wrong was not academic: `analysableSeeds` is the set `synthesizeGenericLaws`
    /// keys on, so marking these unanalysable silently switched off the rescue this file's
    /// `SeededPrivateFunctionTests` exists to guarantee — for every seed the producing linter
    /// emits. Access level belongs in the advice, never in the gate.
    case restrictedFunction

    /// A **type** that owes laws — the linter's domain-type rules. `symbol` is a type name.
    ///
    /// Every other analysable kind names a callable, and that assumption was once written down as
    /// a reason these rules could not seed at all: "the carrier has no callable function attached".
    /// It is false here. `CodableRoundTripTemplate`, `ModelLawTemplate`,
    /// `SequenceViewModelLawTemplate` and the whole `verify-value-semantics` command state laws
    /// over a carrier type with no free function anywhere. A newtype over a primitive is that shape
    /// exactly: `Percentage` can own `0...100` and `String` cannot.
    ///
    /// **Analysable**, for the same reason `restrictedFunction` is — the subject can be named and
    /// laws proposed for it. What it cannot do is be *called*, and the templates that consume a
    /// carrier never try.
    ///
    /// **Joined by type name, not by `(file, symbol)`** — see `SeedFocus.filter`. The producing
    /// rule fires where a raw primitive is *used*, so the seed's `file` is the use site while the
    /// type is usually declared elsewhere. Reusing the function join would miss most of the time.
    case carrier

    /// A kind emitted by a newer producer than this build knows.
    ///
    /// **Treated as not-analysable, deliberately.** The two ways to be wrong here are not
    /// symmetric. Guess "analysable" and a future refactor-pending kind (a pure closure, say) gets
    /// focused on, refused, and reported as a zero — silently. Guess "not analysable" and the seed
    /// is merely skipped, *and said out loud*. Never silently narrow to a symbol you do not
    /// understand.
    case unrecognised(String)

    public var isAnalysable: Bool {
        switch self {
        case .pureFunction, .idempotency, .restrictedFunction, .carrier:
            return true

        case .extractableKernel, .unrecognised:
            return false
        }
    }

    public var rawValue: String {
        switch self {
        case .pureFunction:
            return "pure-function"

        case .idempotency:
            return "idempotency"

        case .extractableKernel:
            return "extractable-kernel"

        case .restrictedFunction:
            return "restricted-function"

        case .carrier:
            return "carrier"

        case .unrecognised(let raw):
            return raw
        }
    }
}

extension SeedKind: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "pure-function":
            self = .pureFunction

        case "idempotency":
            self = .idempotency

        case "extractable-kernel":
            self = .extractableKernel

        case "restricted-function":
            self = .restrictedFunction

        case "carrier":
            self = .carrier

        default:
            self = .unrecognised(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
