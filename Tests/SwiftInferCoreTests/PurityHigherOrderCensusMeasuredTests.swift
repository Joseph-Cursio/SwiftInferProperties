import Foundation
import SwiftEffectInference
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// **Census with a standing verdict — read this header before building
/// parameterised purity.** Open item 33, and the first thing it measured was its
/// own premise, which does not hold.
///
/// ## The premise, and why it is inverted
///
/// Item 33 says purity *does not propagate* through a higher-order call: that
/// `map` is pure-if-its-argument-is, that nothing models the conditional form,
/// and that therefore *"every chain terminates at the first `map`/`reduce`/
/// `filter`, which is where the laws are."*
///
/// **Chains do not terminate. They sail straight through.** `map`, `reduce` and
/// `filter` are in neither marker set, and `PurityInferrer` refutes only on
/// markers, totality and — for a throwing function — a propagated `try`. A name
/// it does not recognise refutes nothing, which is exactly what the item 30
/// census measured about *every* unrecognised callee. The probe table below
/// pins all ten shapes; nine reach `.pure`.
///
/// So there is no under-claim to fix. **There is an over-claim.**
///
/// ```swift
/// func f(_ xs: [Int], _ t: (Int) -> Int) -> [Int] { xs.map(t) }   // judged .pure
/// ```
///
/// `f` is pure if and only if `t` is. The analyzer claims it unconditionally,
/// and a caller passing `{ print($0); return $0 }` makes it false. That *is* the
/// `rethrows`-for-purity gap item 33 names — but the error runs the other way,
/// which changes what the fix has to be. A conditional verdict would let the
/// analyzer stop over-claiming; it would not unblock any chain, because no chain
/// is blocked.
///
/// **This is the third time in this line of work that the documented error
/// direction was backwards** — item 30 was the first, item 33 is this one, and
/// both times the code was more permissive than its own doc claimed. The pattern
/// is worth more than either finding: a posture stated in a doc comment is a
/// claim about intent, and intent is not measurable from the same doc.
///
/// ## What this census does NOT establish
///
/// That any *law* is emitted over the over-claiming population. A function
/// taking a closure needs a generatable carrier for that parameter, and whether
/// the templates ever get that far is a separate question this suite does not
/// ask. The claim measured here is about the **verdict and the advisory**, which
/// is where the population is visible today.
@Suite("Census — does purity propagate through a higher-order call?")
struct PurityHigherOrderCensusMeasuredTests {

    // Type unwrapping and call-site collection are in
    // `PurityHigherOrderCensusMeasuredTests+Support.swift`.

    static var corpus: [Subject] { PurityRefutationCensusMeasuredTests.corpus }
    static var verdicts: [PurityVerdict] { PurityRefutationCensusMeasuredTests.verdicts }

    // MARK: - The probe

    /// The ten shapes, and what the shipped oracle answers for each. Written as
    /// a table rather than ten tests because the *pattern* is the finding: only
    /// the one with a literal impurity in it refutes.
    static let probe: [(label: String, source: String)] = [
        ("literal closure map", "func f(_ xs: [Int]) -> [Int] { xs.map { $0 * 2 } }"),
        ("reduce literal", "func f(_ xs: [Int]) -> Int { xs.reduce(0) { $0 + $1 } }"),
        ("filter literal", "func f(_ xs: [Int]) -> [Int] { xs.filter { $0 > 0 } }"),
        ("chained map/filter/reduce",
         "func f(_ xs: [Int]) -> Int { xs.map { $0 * 2 }.filter { $0 > 0 }.reduce(0, +) }"),
        ("function-typed PARAMETER", "func f(_ xs: [Int], _ t: (Int) -> Int) -> [Int] { xs.map(t) }"),
        ("@escaping parameter", "func f(_ xs: [Int], _ t: @escaping (Int) -> Int) -> [Int] { xs.map(t) }"),
        ("parameter called directly", "func f(_ x: Int, _ t: (Int) -> Int) -> Int { t(x) }"),
        ("closure through a local let",
         "func f(_ xs: [Int]) -> [Int] { let g: (Int) -> Int = { $0 }; return xs.map(g) }"),
        ("nested named function", "func f(_ xs: [Int]) -> [Int] { func g(_ i: Int) -> Int { i }; return xs.map(g) }"),
        ("IMPURE closure literal", "func f(_ xs: [Int]) -> [Int] { xs.map { print($0); return $0 } }")
    ]

    static func verdict(ofFirstFunctionIn source: String) -> PurityVerdict? {
        let tree = Parser.parse(source: source)
        guard let function = tree.statements.lazy
            .compactMap({ $0.item.as(FunctionDeclSyntax.self) }).first else { return nil }
        return SoundPurity.verdict(for: function)
    }

    /// **The premise, falsified.** Nine of the ten shapes reach `.pure`,
    /// including all three that hand the analyzer a function it cannot see. The
    /// only refutation is the one with `print` written inside the literal — a
    /// marker in the body, which is the refuter that was always there.
    @Test("a higher-order call does not terminate a chain — it is waved through")
    func chainsDoNotTerminate() {
        let pure = Self.probe.filter { Self.verdict(ofFirstFunctionIn: $0.source) == .pure }
        #expect(
            pure.count == Self.probe.count - 1,
            "\(pure.count) of \(Self.probe.count) reached .pure — expected all but the impure literal"
        )
        #expect(Self.verdict(ofFirstFunctionIn: Self.probe[9].source) == .refuted)
    }

    /// **The over-claim, isolated.** A function whose purity is *conditional on
    /// an argument the caller supplies* is claimed pure outright. This is the
    /// shape item 33 describes as `rethrows` semantics for purity; what it gets
    /// wrong is which way the analyzer currently errs.
    @Test("a function-typed parameter does not qualify the verdict at all")
    func aFunctionTypedParameterIsInvisible() {
        let conditional = "func f(_ xs: [Int], _ t: (Int) -> Int) -> [Int] { xs.map(t) }"
        let unconditional = "func f(_ xs: [Int]) -> [Int] { xs.map { $0 } }"
        #expect(Self.verdict(ofFirstFunctionIn: conditional) == .pure)
        #expect(
            Self.verdict(ofFirstFunctionIn: conditional) == Self.verdict(ofFirstFunctionIn: unconditional),
            "the conditional and unconditional forms are indistinguishable in the verdict"
        )
    }

    // MARK: - The population

    /// Non-refuted functions taking at least one function-typed parameter — the
    /// population whose purity is conditional and claimed unconditionally.
    static let conditional: [ConditionalRow] = zip(corpus, verdicts)
        .filter { $0.1 != .refuted }
        .compactMap { subject, verdict in
            let parameters = subject.function.signature.parameterClause.parameters
            let functionTyped = parameters.filter { isFunctionType($0.type) }
            guard !functionTyped.isEmpty else { return nil }
            return ConditionalRow(
                subject: subject,
                verdict: verdict,
                functionParameters: functionTyped.map { ($0.secondName ?? $0.firstName).text },
                hasAttributedParameter: functionTyped.contains(where: isAttributed)
            )
        }

    static let conditionalNames: Set<String> = Set(conditional.map(\.subject.name))

    /// **The base rate.** Call sites in this package that hand a conditionally
    /// pure function a closure literal the oracle *refutes*. Each is a caller
    /// making a `.pure`-claimed function impure in practice.
    static let impureArguments: [ClosureArgument] = closureArguments.filter {
        !$0.isPure && conditionalNames.contains($0.calleeName)
    }

    // MARK: - The verdict

    /// The population is real and worth a number, but it is a **claim** count,
    /// not a defect count — the distinction items 40 and 30 both turned on.
    @Test("the conditionally-pure population is non-trivial")
    func theOverClaimHasAPopulation() {
        #expect(Self.conditional.count > 20, "\(Self.conditional.count) conditionally-pure rows")
        #expect(
            Self.conditional.allSatisfy { !$0.functionParameters.isEmpty },
            "every row must name the parameter its purity depends on"
        )
    }

    /// The instrument can see an impure closure at all — otherwise a base rate
    /// of zero would be indistinguishable from a collector that found nothing.
    /// Scored over *every* call site, not only the conditionally-pure ones.
    @Test("the closure oracle refutes something somewhere in this corpus")
    func theBaseRateInstrumentIsNotBlind() {
        let refuted = Self.closureArguments.filter { !$0.isPure }
        #expect(
            !refuted.isEmpty,
            "no closure literal anywhere in Sources/ is refuted — the instrument is blind"
        )
    }

    // MARK: - The finding this census was not looking for — now FIXED upstream

    /// Names that `throwsOnlyItsOwnErrors`' **own doc** lists as the impurities
    /// the `throws` gate used to mask — *"`Process`, `Pipe`, `FileHandle`,
    /// `String(contentsOf:)`, `Data(contentsOf:)`, the SQLite surface"*.
    ///
    /// That gate re-closed the hole for **throwing** functions only. A
    /// non-throwing function that used them was waved through, and
    /// `FileHandle.standardError.write(_:)` does not throw — it is the most
    /// common non-throwing I/O call in a Swift CLI. This package's own
    /// `writeDiagnostic(_:)` is exactly that shape, and was judged `.pure`.
    ///
    /// **These three are now in `sideEffectMarkers` (SEI `3ea25f2`)**, so this set
    /// is no longer "the names in neither marker set" — it is the *witness list*
    /// for the fix, and `maskedIOIsRefuted` holds them refuted. The other two
    /// names in that doc's list stay out of both mechanisms deliberately:
    /// `String` and `Data` are matched by bare identifier and are among the most
    /// common pure types in Swift, and `String(contentsOf:)` / `Data(contentsOf:)`
    /// throw, so the `try` gate already reaches them.
    static let maskedIOMarkers: Set<String> = ["FileHandle", "Process", "Pipe"]

    /// Non-refuted functions whose body names one of them.
    struct UnmaskedIORow {
        let subject: Subject
        let verdict: PurityVerdict
        let names: [String]
    }

    static let unmaskedIO: [UnmaskedIORow] = zip(corpus, verdicts)
        .filter { $0.1 != .refuted }
        .compactMap { subject, verdict in
            guard let body = subject.function.body else { return nil }
            let hits = Set(body.tokens(viewMode: .sourceAccurate).map(\.text))
                .intersection(maskedIOMarkers)
            return hits.isEmpty ? nil : UnmaskedIORow(subject: subject, verdict: verdict, names: hits.sorted())
        }

    /// **CLOSED at SEI `3ea25f2`, and this assertion is inverted rather than
    /// deleted.** It used to pin the hole *open* — `!unmaskedIO.isEmpty`, with the
    /// instruction *"if the marker set grew, delete this test with the fix"*. The
    /// marker set grew: `50125f8` put `FileHandle` / `Process` / `Pipe` into
    /// `sideEffectMarkers`, and the falsifier fired on the very run that bumped
    /// the pin, which is the notification a comment would not have given.
    ///
    /// **Inverted instead of deleted because the two directions guard different
    /// things.** Deleting it would leave nothing to notice the hole reopening —
    /// and it can reopen without anyone touching this repo, since the marker set
    /// lives in a pinned dependency. The falsifier's job was to fail when the gap
    /// closed; this one's is to fail if it ever reopens. Same measurement, and
    /// the probe is kept because the count alone cannot distinguish *"the oracle
    /// refutes these"* from *"the corpus stopped exhibiting the shape"*.
    ///
    /// Kept in *this* suite rather than filed away because of how it was found:
    /// the base rate for item 33's over-claim measured zero, and the reason it
    /// measured zero is that the instrument shared the blindness. The closure
    /// handed to `EffectResolver.resolve(diagnostic:)` is
    /// `{ diagnostics.writeDiagnostic($0) }`, which writes to standard error and
    /// which `isPure(_ closure:)` called pure. **A zero measured with a blind
    /// instrument is not a zero** — and that instrument is no longer blind, which
    /// is why item 33's base rate is worth re-taking rather than inheriting.
    @Test("the I/O the throws gate used to mask is refuted, and stays refuted")
    func maskedIOIsRefuted() {
        let probes = Self.maskedIOMarkers.sorted().map { name -> String in
            let source = "func f(_ h: FileHandle) { _ = \(name).self; _ = h }"
            let answer = Self.verdict(ofFirstFunctionIn: source).map { "\($0)" } ?? "?"
            return "\(name)=\(answer)"
        }
        #expect(
            Self.unmaskedIO.isEmpty,
            """
            \(Self.unmaskedIO.count) non-refuted functions in Sources/ name \
            FileHandle/Process/Pipe again, so the non-throwing I/O hole has REOPENED — \
            check whether the SEI pin moved back below 3ea25f2. \
            First few: \(Self.unmaskedIO.prefix(5).map { "\($0.subject.name)=\($0.verdict)" }). \
            Probe: \(probes)
            """
        )
        #expect(
            probes.allSatisfy { $0.hasSuffix("=refuted") },
            "each marker must refute a non-throwing function on its own: \(probes)"
        )
    }

    // MARK: - The census

    @Test("census — higher-order purity, and who is claiming what")
    func census() {
        var lines = ["probe — the shipped verdict for each higher-order shape:"]
        for entry in Self.probe {
            let verdict = Self.verdict(ofFirstFunctionIn: entry.source)
                .map { "\($0)" } ?? "unparsed"
            lines.append("  \(verdict.padding(toLength: 9, withPad: " ", startingAt: 0)) \(entry.label)")
        }

        lines.append("population — non-refuted functions with a function-typed parameter:")
        let nonRefuted = Self.verdicts.filter { $0 != .refuted }.count
        lines.append("  total: \(Self.conditional.count) of \(nonRefuted) non-refuted")
        lines.append("  .pure: \(Self.conditional.filter { $0.verdict == .pure }.count)")
        lines.append("  .pureButPartial: \(Self.conditional.filter { $0.verdict == .pureButPartial }.count)")
        lines.append("  with @escaping/@autoclosure: \(Self.conditional.filter(\.hasAttributedParameter).count)")

        lines.append("base rate — call sites handing one of them a REFUTED closure literal:")
        lines.append("  closure literals passed anywhere in Sources/: \(Self.closureArguments.count)")
        lines.append("  ...of which the oracle refutes: \(Self.closureArguments.filter { !$0.isPure }.count)")
        lines.append("  ...passed to a conditionally-pure function: \(Self.impureArguments.count)")
        for entry in Self.impureArguments.prefix(20) {
            lines.append("    \(entry.file): \(entry.calleeName)")
        }

        lines.append("finding NOT looked for — I/O the throws gate used to mask, without throws:")
        lines.append("  non-refuted functions naming FileHandle/Process/Pipe: \(Self.unmaskedIO.count)")
        for entry in Self.unmaskedIO.prefix(20) {
            lines.append("    \(entry.subject.file):\(entry.subject.name)"
                + " [\(entry.verdict)] -> \(entry.names.joined(separator: ", "))")
        }

        lines.append("the population, by callee (top 20):")
        for row in Self.conditional.sorted(by: { $0.subject.name < $1.subject.name }).prefix(20) {
            lines.append("  \(row.subject.file):\(row.subject.name)"
                + " (\(row.functionParameters.joined(separator: ", ")))"
                + (row.hasAttributedParameter ? " [attributed]" : ""))
        }
        print(lines.joined(separator: "\n"))
    }
}
