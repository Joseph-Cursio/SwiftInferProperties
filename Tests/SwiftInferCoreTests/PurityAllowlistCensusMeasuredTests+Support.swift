import Foundation
import SwiftEffectInference
import SwiftSyntax

@testable import SwiftInferCore

/// The callee taxonomy, the collector, and the seed-set arithmetic for
/// `PurityAllowlistCensusMeasuredTests`. Split out only for the 400-line file
/// cap; the reasoning that governs all three lives in that suite's header.
extension PurityAllowlistCensusMeasuredTests {

    /// Where a called name resolves to, from this leaf's point of view.
    enum CalleeOrigin: String, CaseIterable, Comparable {
        /// A `func` declared inside the caller's own body — a local helper, and
        /// nothing an allowlist would ever have to name.
        case nested

        /// A function declared elsewhere under this package's `Sources/`,
        /// matched by **bare name**. Overloads collapse; see the suite header
        /// for what that costs each number.
        case package

        /// A name in `PurityInferrer`'s marker sets. Unreachable from a
        /// non-refuted body by construction — counted as this census's own
        /// control, and asserted to be zero.
        case marker

        /// Everything else — stdlib, Foundation, SwiftSyntax, a member of some
        /// type this leaf never resolves. **This is item 30's population.**
        case unrecognised

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The syntactic shape the name was read off, kept because the two imply
    /// very different seed sets: `free` is a finite list of stdlib free
    /// functions and initialisers, `member` is every method name in every
    /// library on the import path.
    enum CallShape: String, CaseIterable, Comparable {
        /// `min(a, b)`, `String(x)` — a bare `DeclReferenceExpr` callee.
        case free

        /// `xs.map { … }`, `text.hasPrefix(p)` — a `MemberAccessExpr` callee.
        case member

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// One called name, at one shape. Two shapes of the same name are two
    /// entries: an allowlist that admits `Set(…)` has said nothing about
    /// `xs.Set` and vice versa.
    struct Callee: Hashable, Comparable {
        let name: String
        let shape: CallShape

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.name, lhs.shape) < (rhs.name, rhs.shape)
        }
    }

    /// A non-refuted subject, with every callee its body reaches, classified.
    struct CallProfile {
        let subject: PurityRefutationCensusMeasuredTests.Subject
        let verdict: PurityVerdict
        let byOrigin: [CalleeOrigin: Set<Callee>]

        var unrecognised: Set<Callee> { byOrigin[.unrecognised] ?? [] }
        var packageCallees: Set<Callee> { byOrigin[.package] ?? [] }
    }

    // MARK: - Seed-set arithmetic

    /// How many subjects a seed set of `size` frees, under both readings.
    ///
    /// The two differ for exactly the reason item 32 names about blocking
    /// callees, one level up: a subject with three unrecognised callees is freed
    /// by **none** of them individually. `touched` is what a frequency table
    /// reports; `freed` is what the seed set actually buys.
    struct Coverage {
        let size: Int
        let touched: Int
        let freed: Int
    }

    /// Coverage for the `size` most frequent unrecognised names, frequency
    /// counted in **subjects**, never occurrences — rows moved, not laws gained.
    static func coverage(ofTopMostFrequent size: Int, over profiles: [CallProfile]) -> Coverage {
        let seed = Set(frequencyOrderedUnrecognisedNames(over: profiles).prefix(size))
        let blocked = profiles.filter { !$0.unrecognised.isEmpty }
        return Coverage(
            size: size,
            touched: blocked.filter { !$0.unrecognised.isDisjoint(with: seed) }.count,
            freed: blocked.filter { $0.unrecognised.isSubset(of: seed) }.count
        )
    }

    /// Unrecognised callees, most-blocked-subjects first. Ties break on the name
    /// so the order is stable across runs (PRD §16 #6).
    static func frequencyOrderedUnrecognisedNames(over profiles: [CallProfile]) -> [Callee] {
        var subjectsPerCallee: [Callee: Int] = [:]
        for profile in profiles {
            for callee in profile.unrecognised { subjectsPerCallee[callee, default: 0] += 1 }
        }
        return subjectsPerCallee
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map(\.key)
    }

    /// The greedy-with-recompute curve item 32 asks for, applied to axioms
    /// rather than annotations: at each step take the name that **completes**
    /// the most still-blocked subjects, falling back to raw frequency among the
    /// still-blocked when nothing completes anything.
    ///
    /// Returns the seed-set size needed to free each decile of the blocked
    /// population, or `nil` for a decile the search never reaches within
    /// `limit` picks.
    static func greedySeedSetSizes(
        freeingDecilesOf profiles: [CallProfile],
        limit: Int = 600
    ) -> [(decile: Int, size: Int?)] {
        var remaining = profiles.map(\.unrecognised).filter { !$0.isEmpty }
        let blocked = remaining.count
        var sizes: [Int: Int] = [:]
        var picked = 0

        while picked < limit, remaining.contains(where: { !$0.isEmpty }) {
            var completions: [Callee: Int] = [:]
            var frequency: [Callee: Int] = [:]
            for set in remaining where !set.isEmpty {
                if set.count == 1, let only = set.first { completions[only, default: 0] += 1 }
                for callee in set { frequency[callee, default: 0] += 1 }
            }
            guard let choice = frequency.keys.max(by: {
                (completions[$0] ?? 0, frequency[$0] ?? 0, $1) < (completions[$1] ?? 0, frequency[$1] ?? 0, $0)
            }) else { break }

            picked += 1
            for index in remaining.indices { remaining[index].remove(choice) }
            let freed = remaining.filter(\.isEmpty).count
            let decile = blocked == 0 ? 0 : (freed * 10) / blocked
            if decile > 0, sizes[decile] == nil { sizes[decile] = picked }
        }
        return (1...10).map { (decile: $0 * 10, size: sizes[$0]) }
    }
}

// MARK: - The collector

/// Every name a body calls, plus the names it declares locally.
///
/// **Scoped to call expressions on purpose.** A bare `x.count` also runs a
/// getter this leaf cannot see, and admitting property reads would widen the
/// population by an amount this census does not measure. Every number here is
/// therefore a *lower* bound on item 30's exposure, and the suite header says so
/// where it matters.
final class CensusCalleeCollector: SyntaxVisitor {

    private(set) var callees: Set<PurityAllowlistCensusMeasuredTests.Callee> = []
    private(set) var nestedFunctionNames: Set<String> = []

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        nestedFunctionNames.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let callee = Self.callee(of: node.calledExpression) { callees.insert(callee) }
        return .visitChildren
    }

    /// The name and shape of a call's callee, unwrapping the spellings that
    /// wrap one: `Foo<Bar>(…)`, `(foo)(…)`, `foo?.bar(…)`, `foo!.bar(…)`.
    static func callee(of expression: ExprSyntax) -> PurityAllowlistCensusMeasuredTests.Callee? {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return .init(name: reference.baseName.text, shape: .free)
        }
        if let member = expression.as(MemberAccessExprSyntax.self) {
            return .init(name: member.declName.baseName.text, shape: .member)
        }
        if let specialized = expression.as(GenericSpecializationExprSyntax.self) {
            return callee(of: specialized.expression)
        }
        if let tuple = expression.as(TupleExprSyntax.self), tuple.elements.count == 1,
           let only = tuple.elements.first {
            return callee(of: only.expression)
        }
        if let optional = expression.as(OptionalChainingExprSyntax.self) {
            return callee(of: optional.expression)
        }
        if let forced = expression.as(ForceUnwrapExprSyntax.self) {
            return callee(of: forced.expression)
        }
        return nil
    }
}
