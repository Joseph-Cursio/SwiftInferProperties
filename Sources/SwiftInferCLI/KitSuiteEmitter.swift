import Foundation
import PropertyLawCore
import SwiftInferCore

/// **Codegen for the laws PropertyLawKit covers but nothing writes.**
///
/// Measured on this repo: the kit's suites cover **996 laws over 299 carriers**, of which
/// **5 execute**. The gap was never a missing capability — `ProtocolCoverageMap`'s veto
/// suppresses each of those laws with a message that *names* the call
/// (`"checked by PropertyLawKit's check<Protocol>PropertyLaws"`) and generates nothing. It
/// tells you the test exists and leaves you to type ~299 call sites.
///
/// Seeing the tests is worth something on its own, separately from running them: a law you
/// can read is a claim you can disagree with, and `Equatable`'s laws passing on a *broken*
/// type is exactly the case `fixtures/equatable-signal` measured. So this emits source, for
/// a human to read and keep or discard — never applied, per the standing posture.
///
/// ## Derivability is the constraint, and it was measured before this was built
///
/// `check<Protocol>PropertyLaws` takes `using generator:` with **no default**, so every
/// emitted suite needs a `Generator<Value, _>`. `DerivationStrategist` derives one for
/// **180 of 351** covered carriers (51%), covering **598 of 1,153** laws.
///
/// The other half emit too, **commented out**, carrying the kit's own `.todo` reason — which
/// already ends with the exact signature to provide. Emitting them live would produce a file
/// that does not compile; omitting them silently would report half the work as all of it,
/// the "no silent caps" failure. Commented-out is the only option that is both honest and
/// compilable.
///
/// ## What this does not guarantee
///
/// That the live half compiles. `check<Protocol>PropertyLaws` requires `Value: Sendable`,
/// which a `TypeShape` cannot always tell us, and a carrier may be `private` or nested
/// beyond `@testable`'s reach. The output is a **draft for review**, which is why nothing
/// writes it into a build without the author asking.
public enum KitSuiteEmitter {

    /// The four numbers the header reports, bundled so `assemble` stays within the
    /// five-parameter cap.
    struct Counts {
        let liveCarriers: Int
        let blockedCarriers: Int
        let liveLaws: Int
        let blockedLaws: Int
    }

    public struct Emission: Equatable {
        public let source: String
        /// Carriers whose generator derived — emitted as live code.
        public let liveCarriers: Int
        /// Carriers needing a hand-written `gen()` — emitted commented out.
        public let blockedCarriers: Int
        public let liveLaws: Int
        public let blockedLaws: Int
    }

    /// Emit one Swift test file covering every carrier the kit's suites reach.
    ///
    /// - Parameter moduleName: the module under test, for `@testable import`. Carriers are
    ///   frequently `internal`, so a plain `import` would not see them.
    public static func emit(
        findings: [ProtocolCoverageAudit.Finding],
        shapes: [String: PropertyLawCore.TypeShape],
        moduleName: String,
        genericParametersByName: [String: [TypeDecl.GenericParameter]] = [:]
    ) -> Emission {
        // **The whole-module resolver, and leaving it out was the single biggest cost.**
        //
        // `DerivationStrategist.strategy(for:)` defaults `resolve` to `{ _ in nil }`, which
        // means a member typed as another type IN THE SAME CORPUS does not resolve — the
        // strategist can see `Money` but not that `Money.currency: Currency` is itself
        // derivable. The first version of this emitter took that default and measured 51%
        // derivable; `scaffold` had been passing a resolver since WS-6.
        let resolver = GeneratorResolver(types: Array(shapes.values))
        let resolve = resolver.customTypeGenerator
        var live: [String] = []
        var blocked: [String] = []
        var liveCarriers = 0, blockedCarriers = 0, liveLaws = 0, blockedLaws = 0

        for finding in findings.sorted(by: { $0.typeName < $1.typeName }) {
            guard let shape = shapes[finding.typeName] else { continue }
            let suites = suiteConformances(for: finding)
            guard !suites.isEmpty else { continue }
            switch classify(
                finding: finding, shape: shape, suites: suites, resolve: resolve,
                genericParametersByName: genericParametersByName
            ) {
            case .live(let text):
                liveCarriers += 1
                liveLaws += finding.coveredLaws.count
                live.append(text)

            case .blocked(let text):
                blockedCarriers += 1
                blockedLaws += finding.coveredLaws.count
                blocked.append(text)
            }
        }

        return Emission(
            source: assemble(
                live: live,
                blocked: blocked,
                moduleName: moduleName,
                counts: Counts(
                    liveCarriers: liveCarriers, blockedCarriers: blockedCarriers,
                    liveLaws: liveLaws, blockedLaws: blockedLaws
                )
            ),
            liveCarriers: liveCarriers,
            blockedCarriers: blockedCarriers,
            liveLaws: liveLaws,
            blockedLaws: blockedLaws
        )
    }

    /// The conformances worth emitting a suite for, with subsumed ones dropped.
    ///
    /// **`Hashable`'s law set already contains `Equatable`'s** — `ProtocolCoverageMap` bakes
    /// transitive coverage in, so emitting both would run reflexivity, symmetry and
    /// transitivity twice and read as two findings where there is one. A conformance is
    /// dropped when its laws are a strict subset of another declared conformance's, which
    /// needs no model of Swift's protocol hierarchy — the sets already encode it.
    /// Conformances whose kit suite needs an argument this emitter cannot derive.
    ///
    /// `checkStrideablePropertyLaws` requires `strideGenerator: Generator<Value.Stride, _>`,
    /// and `Stride` is an associated type the scanner does not resolve — for `_HashSlot` it
    /// happens to be `Int`, but guessing would emit `missing argument for parameter
    /// 'strideGenerator'` wherever it is not. Measured: that error, plus
    /// `generic parameter 'StrideShrinker' could not be inferred`, in `HashTreeCollections`.
    ///
    /// **This is a codegen limit, not a coverage claim.** The kit does run
    /// `Strideable.distanceRoundTrip`, so `ProtocolCoverageMap`'s entry stays true and
    /// `discover` is right to defer; what is missing is our ability to write the call. A
    /// carrier reaching only this conformance is reported blocked, with the reason.
    static let conformancesNeedingUnderivableArguments: Set<String> = ["Strideable"]

    static func suiteConformances(for finding: ProtocolCoverageAudit.Finding) -> [String] {
        let declared = finding.declaredCoveringConformances
            .filter { !conformancesNeedingUnderivableArguments.contains($0) }
        let kept = declared.filter { candidate in
            guard let mine = ProtocolCoverageMap.protocolCoverage[candidate], !mine.isEmpty else {
                return false
            }
            return !declared.contains { other in
                guard other != candidate,
                      let theirs = ProtocolCoverageMap.protocolCoverage[other] else { return false }
                return mine.isStrictSubset(of: theirs)
            }
        }
        return kept.sorted()
    }

    /// One carrier's verdict: an emitted suite, or a commented-out block with the reason.
    enum CarrierBlock {
        case live(String)
        case blocked(String)
    }

    /// Decide a single carrier's fate. Extracted from `emit` on 2026-08-02, when the
    /// concrete-instantiation gate pushed that function past the 50-line body cap.
    ///
    /// **The order of the gates is the point.** Naming the carrier comes first, because a
    /// generic type that cannot be instantiated cannot produce a compiling call however good
    /// its generator is. `Deque.self` was emitted behind a derivable generator that nothing
    /// could reach, and the resulting compile error read as a generator problem.
    static func classify(
        finding: ProtocolCoverageAudit.Finding,
        shape: PropertyLawCore.TypeShape,
        suites: [String],
        resolve: (String) -> DerivationStrategist.ComposedGenerator?,
        genericParametersByName: [String: [TypeDecl.GenericParameter]]
    ) -> CarrierBlock {
        guard let carrierName = ConcreteInstantiation.rendered(
            qualifiedTypeName: finding.typeName,
            genericParametersByName: genericParametersByName
        ) else {
            return .blocked(blockedBlock(
                finding,
                suites: suites,
                reason: ConcreteInstantiation.declineReason(
                    qualifiedTypeName: finding.typeName,
                    genericParametersByName: genericParametersByName
                ) ?? "",
                carrierName: finding.typeName
            ))
        }
        let strategy = DerivationStrategist.strategy(for: shape, resolve: resolve)
        let generator = boundingNumerics(
            GeneratorExpressionEmitter.expression(
                typeName: finding.typeName, strategy: strategy
            )
        )
        if let overrun = typeCheckerOverrun(generator) {
            // Derives, but the composed expression is big enough to risk a compiler
            // type-check timeout. Blocked rather than emitted — see `typeCheckerOverrun`.
            return .blocked(blockedBlock(
                finding, suites: suites, reason: overrun, carrierName: carrierName
            ))
        }
        if case .todo(let reason) = strategy {
            return .blocked(blockedBlock(
                finding, suites: suites, reason: reason, carrierName: carrierName
            ))
        }
        return .live(liveBlock(
            finding, suites: suites, generator: generator,
            isCaseIterable: strategy == .caseIterable, carrierName: carrierName
        ))
    }

    // MARK: - Blocks

    /// `carrierName` is the name to WRITE — `Deque<Int>` where `finding.typeName` is
    /// `Deque`. Kept separate from `typeName` on purpose: the display text, the test-function
    /// name and the `KitEvidenceRecorder` key all want the bare identifier, and only the
    /// two `.self` positions want the instantiation. Collapsing them would put angle brackets
    /// in a Swift function name.
    static func liveBlock(
        _ finding: ProtocolCoverageAudit.Finding,
        suites: [String],
        generator: String,
        isCaseIterable: Bool,
        carrierName: String
    ) -> String {
        suites.map { conformance in
            """
                /// `\(finding.typeName)` conforms to `\(conformance)`, so the kit checks \
            these laws.
                @Test("\(finding.typeName) — \(conformance) laws")
                func \(functionName(finding.typeName, conformance))() async throws {
                    let results = try await check\(conformance)PropertyLaws(
                        for: \(carrierName).self,
                        using: \(generator)\(options(conformance, isCaseIterable: isCaseIterable))
                    )
                    // Strict-tier only, matching `EnforcementMode.default` — which the kit
                    // already enforces by throwing. A blanket `allSatisfy { .passed }` is
                    // STRICTER THAN THE KIT INTENDS and fails on advisory findings: measured
                    // here, `Hashable.distribution` (Heuristic) fails for every CaseIterable
                    // enum, because 25 cases cannot fill 1000 trials with unique hashes. No
                    // generator fixes that; the domain is the type.
                    #expect(results.allSatisfy { $0.tier != .strict || $0.outcome == .passed })
                    // Feeds the verdicts back to `discover`, which demotes `==`-shaped laws
                    // about a carrier whose equality the kit refuted.
                    try KitEvidenceRecorder.record(
                        results, for: "\(finding.typeName)", packageRoot: Self.packageRoot
                    )
                }
            """
        }
        .joined(separator: "\n\n")
    }

    static func blockedBlock(
        _ finding: ProtocolCoverageAudit.Finding,
        suites: [String],
        reason: String,
        carrierName: String
    ) -> String {
        let calls = suites.map { conformance in
            "    //     _ = try await check\(conformance)PropertyLaws("
                + "for: \(carrierName).self, using: \(carrierName).gen())"
        }
        .joined(separator: "\n")
        return """
            // \(finding.typeName) — \(finding.coveredLaws.count) law(s), \
        BLOCKED on a generator.
            // \(reason)
        \(calls)
        """
    }

    /// **Bound the derived numeric leaves, because an aggregating carrier traps.**
    ///
    /// `GeneratorExpressionEmitter` emits `Gen<Int>.int()`, which draws the FULL `Int` range.
    /// That is correct for a law about one value and fatal for a carrier that sums its
    /// members: `Score.init(signals:)` does `.reduce(0, +)` over up to eight weights, so a
    /// full-range draw overflows and the process dies with **SIGTRAP** — measured, as an
    /// `exited with unexpected signal code 5` that killed the whole run rather than failing
    /// one test.
    ///
    /// ±10_000 is not a new invention: it is the bound the verify path already draws from,
    /// for the same reason, recorded in the multiplicative-homomorphism warning
    /// (*"MIND OVERFLOW … the property must be checked over a BOUNDED domain (the verifier
    /// draws from ±10_000)"*). Matching it keeps one answer to the question in the repo.
    ///
    /// **The trade is real and worth naming**: a bounded draw cannot find an overflow bug at
    /// the numeric extremes. That is the same call the verifier already made — a law about
    /// sign or measure logic is reachable in ±10_000; one about `Int.max` is not.
    static func boundingNumerics(_ expression: String) -> String {
        expression
            .replacingOccurrences(of: "Gen<Int>.int()", with: "Gen<Int>.int(in: -10_000...10_000)")
            .replacingOccurrences(of: "Gen<UInt64>.uint64()", with: "Gen<UInt64>.uint64(in: 0...10_000)")
    }

    /// **Nesting depth at which the emitted generator stops being worth it.**
    ///
    /// Passing the whole-module resolver took derivation from 51% to 78% of carriers, but
    /// composed generators nest: a type whose members are themselves user types emits
    /// `zip(zip(zip(...)))`, and Swift's type checker is superlinear in that nesting. Measured
    /// on `SwiftInferCore`: expressions reached **8 nested `zip(`s and 1,935 characters**, and
    /// the build failed with *"the compiler is unable to type-check this expression in
    /// reasonable time"*.
    ///
    /// This repo has been bitten by exactly that before — a 12-arm `+` chain that compiled
    /// locally and tripped CI's type-check timeout, silently failing every push for eight
    /// commits (`bbd634c`). A generated file that compiles on the author's machine and not on
    /// the reviewer's is worse than one that admits the limit up front.
    static let maximumZipNesting = 4

    /// Non-nil when the expression is too complex to emit as live code.
    static func typeCheckerOverrun(_ expression: String) -> String? {
        let nesting = expression.components(separatedBy: "zip(").count - 1
        guard nesting > maximumZipNesting else { return nil }
        return "Generator DERIVES, but the composed expression nests \(nesting) `zip`s "
            + "(limit \(maximumZipNesting)) and risks a compiler type-check timeout. Emitted "
            + "commented out rather than shipped as a build failure. Provide `static func "
            + "gen() -> Generator<T, some SendableSequenceType>` to replace the composition "
            + "with something the type checker can handle."
    }

    /// Skip `Hashable.distribution` for a `CaseIterable` enum, and nothing else.
    ///
    /// **Measured, not anticipated.** Running the first generated file, `KnownProperty` and
    /// `TemplateName` were the only two failures of 126: *"1000 samples produced only 25
    /// unique hashValues (ratio 0.025)"*. The law is right and the type is right — the
    /// generator draws from `allCases`, so the domain is the case list and 1000 trials
    /// cannot produce more distinct hashes than there are cases. No generator fixes it.
    ///
    /// Scoped to `.caseIterable` deliberately. On a wide domain a bad `hash(into:)` really
    /// does show up as clustering, so suppressing `distribution` everywhere would trade a
    /// real signal for a green run — the exact bargain `fixtures/toolchain-coverage` warns
    /// against when it says a reader who narrows a generator "should not widen it to silence
    /// the distribution law".
    ///
    /// The kit records a swift-testing Issue for a Heuristic violation even though
    /// `EnforcementMode.default` does not throw, so an assertion tightened to Strict is not
    /// enough on its own — the suppression is what keeps the emitted suite green.
    static func options(_ conformance: String, isCaseIterable: Bool) -> String {
        // **The `elementSameResult:` overload, always, for the Sequence chain.**
        //
        // The default overload requires `Value.Element: Equatable`, and a dictionary-shaped
        // carrier's Element is a TUPLE — `(key: Key, value: Value)` — which cannot conform to
        // a protocol. Measured: `OrderedDictionary`, `OrderedDictionary.Elements` and
        // `_Bitmap` all failed with "cannot conform to 'Equatable'".
        //
        // The kit shipped these overloads for exactly this (its own note calls it "a missing
        // conformance can be a harness problem, not a type problem"). Passing
        // `{ $0 == $1 }` unconditionally is strictly more permissive than the default: it
        // compiles for any Equatable element AND for a tuple of Equatables, since Swift
        // defines `==` on tuples up to six members. A carrier whose Element is neither would
        // not have compiled under the default overload either.
        if conformance == "Sequence" || conformance == "Collection" {
            return ",\n                        elementSameResult: { $0 == $1 }"
        }
        guard isCaseIterable, conformance == "Hashable" else { return "" }
        return """
        ,
                        options: LawCheckOptions(suppressions: [
                            // A CaseIterable domain cannot fill 1000 trials with distinct
                            // hashes; the law is degenerate here by construction, not failing.
                            .skip(
                                LawIdentifier(protocolName: "Hashable", lawName: "distribution"),
                                reason: "domain is `allCases` — fewer values than trials"
                            )
                        ])
        """
    }

    /// `VerifyHarness.LookupResult` + `Equatable` → `verifyHarnessLookupResultEquatable`.
    /// Nested types are the common case here and a dot is not legal in an identifier.
    static func functionName(_ typeName: String, _ conformance: String) -> String {
        let parts = typeName.split(separator: ".").map(String.init)
        let head = parts.first.map { $0.prefix(1).lowercased() + $0.dropFirst() } ?? ""
        let tail = parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return head + tail.joined() + conformance
    }
}
