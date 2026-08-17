import Foundation
import SwiftEffectInference
import SwiftSyntax

@testable import SwiftInferCore

/// The blocking-callee extraction and the join simulation for
/// `PurityBlockingCalleeCensusMeasuredTests`. Split out for the 400-line file
/// cap only; the reasoning that governs both lives in that suite's header.
extension PurityBlockingCalleeCensusMeasuredTests {

    typealias Callee = PurityAllowlistCensusMeasuredTests.Callee
    typealias Subject = PurityRefutationCensusMeasuredTests.Subject

    /// One row of the item 29 bucket that is blocked by ignorance alone: it
    /// `throws`, its body `try`s into something, and nothing in it refutes
    /// purity on its own.
    struct BlockedRow {
        let subject: Subject

        /// **Conservative.** Every callee appearing anywhere inside a `try`
        /// expression. One `try` covers a whole expression in Swift, so in
        /// `try foo(index(x))` either call may be the throwing one; requiring
        /// both to resolve under-reports what a join would free, which is the
        /// safe direction for a leverage claim.
        let allUnderTry: Set<Callee>

        /// **Optimistic.** Only the outermost call of each `try` expression —
        /// the one that throws in the ordinary case. The two together are a
        /// band, and the census reports both rather than picking.
        let outermostUnderTry: Set<Callee>
    }

    /// How a name's declarations stand, for the purposes of the join. A name is
    /// only usable when **every** declaration carrying it is settled, because
    /// name-keyed resolution cannot tell two same-named functions apart.
    enum NameStatus {
        /// Every declaration is `.pure` or `.pureButPartial` today.
        case settled
        /// Declared in the package, and at least one declaration is refuted.
        case blocked
        /// Not declared in this package at all.
        case foreign
    }

    /// The join, simulated. Returns the rows freed and the number of hops it
    /// took, so the one-hop and fixpoint answers can be compared — that
    /// comparison is what says whether multi-hop is worth its budget.
    ///
    /// A row is freed only when **all** of its blockers are settled, which is
    /// item 32's rule applied at the row level rather than the cause level: a
    /// function blocked by three callees is freed by none of them individually.
    static func simulateJoin(
        rows: [BlockedRow],
        blockers: KeyPath<BlockedRow, Set<Callee>>,
        status: [String: NameStatus],
        maxHops: Int
    ) -> (freed: [BlockedRow], hops: Int) {
        var settled = Set(status.filter { $0.value == .settled }.keys)
        var remaining = rows
        var freed: [BlockedRow] = []
        var hops = 0

        while hops < maxHops {
            hops += 1
            let (nowFree, stillBlocked) = remaining.reduce(
                into: ([BlockedRow](), [BlockedRow]())
            ) { result, row in
                if row[keyPath: blockers].allSatisfy({ settled.contains($0.name) }) {
                    result.0.append(row)
                } else {
                    result.1.append(row)
                }
            }
            if nowFree.isEmpty { break }
            freed.append(contentsOf: nowFree)
            remaining = stillBlocked
            // A freed row's own name becomes usable only when every declaration
            // carrying it is settled or freed — the same all-declarations rule.
            let freedNames = Set(nowFree.map(\.subject.name))
            for name in freedNames where !remaining.contains(where: { $0.subject.name == name }) {
                if status[name] == .blocked { settled.insert(name) }
            }
        }
        return (freed, hops)
    }
}

// MARK: - Extraction

/// Every callee reached under a `try`, at both readings.
///
/// This is the fact item 31 says never leaves the inferrer: at the point
/// `throwsOnlyItsOwnErrors` gives up, it knows **which** callee it gave up on,
/// and `PurityVerdict.refuted` carries no room to say so. Re-deriving it here
/// is what lets the population be sized before anything is built to carry it.
final class CensusBlockingCalleeCollector: SyntaxVisitor {

    private(set) var all: Set<PurityAllowlistCensusMeasuredTests.Callee> = []
    private(set) var outermost: Set<PurityAllowlistCensusMeasuredTests.Callee> = []

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        let inner = CensusCalleeCollector(viewMode: .sourceAccurate)
        inner.walk(node.expression)
        all.formUnion(inner.callees)

        if let call = Self.outermostCall(in: node.expression),
           let callee = CensusCalleeCollector.callee(of: call.calledExpression) {
            outermost.insert(callee)
        }
        return .visitChildren
    }

    /// The call the `try` is actually about — the outermost one, unwrapping the
    /// spellings that wrap an expression without being a call themselves.
    private static func outermostCall(in expression: ExprSyntax) -> FunctionCallExprSyntax? {
        if let call = expression.as(FunctionCallExprSyntax.self) { return call }
        if let awaited = expression.as(AwaitExprSyntax.self) {
            return outermostCall(in: awaited.expression)
        }
        if let optional = expression.as(OptionalChainingExprSyntax.self) {
            return outermostCall(in: optional.expression)
        }
        if let forced = expression.as(ForceUnwrapExprSyntax.self) {
            return outermostCall(in: forced.expression)
        }
        if let tuple = expression.as(TupleExprSyntax.self), tuple.elements.count == 1,
           let only = tuple.elements.first {
            return outermostCall(in: only.expression)
        }
        // `try x.map { … }` with the call further in, `try await foo`, a bare
        // `try someThrowingProperty` — no single outermost call to name.
        return nil
    }
}
