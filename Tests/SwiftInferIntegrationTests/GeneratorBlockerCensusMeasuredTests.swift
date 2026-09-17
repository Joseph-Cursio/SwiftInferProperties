import Foundation
import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// **Why can the tool not derive a generator for this type?** — asked of the resolver, which now
/// answers.
///
/// `docs/measurements/missing-generator-census.md` measured the population — 1,326 of 2,058
/// emitted stubs carry at least one `.gen()` the tool could not derive — and §3 attributed causes
/// with an earlier version of this probe. That version had to INFER: `GeneratorResolver` returned
/// `nil` from five places and reported none of them, so the probe reconstructed two paths from
/// the resolver's inputs and read the third off the shape, leaving **370 types (18.4%) as
/// *has members — reason not visible here***.
///
/// SwiftPropertyLaws 4.7.0 (#50–#53) records the reason where the resolver gives up and returns
/// it from `resolutionFailure(forTypeName:)`, carrying the strategist's own `.todo` sentence for
/// `.noStrategy`. **So this probe no longer infers anything.** It asks which types are unbuildable
/// through the whole chain the emitter uses, then asks the resolver why.
///
/// ## How a `.noStrategy` reason is bucketed — without a second copy of the kit's table
///
/// The kit buckets its own reasons with a substring table (`PropertyLawDiscoveryTool
/// .todoCategory`), `internal` to an executable target and so not importable. Restating that
/// table here would be the copy that drifts the day a reason is reworded. Instead a reason is
/// reduced to its **sentence shape**: every backticked name becomes `…`. The buckets are then
/// the resolver's own wording, and follow it when it changes.
///
/// **Opt-in**, like `TrapAttributionCensusMeasuredTests`: it scans a corpus and answers a
/// question that only changes when re-asked.
///
///     SWIFT_INFER_GENERATOR_CENSUS=/path/to/corpus swift test --filter GeneratorBlockerCensus
///
/// Batched anyway, because `SubprocessBatchCoverageTests` requires every `*MeasuredTests` suite
/// to be scheduled somewhere; disabled, it costs that batch nothing.
@Suite(
    "Generator blockers — why the resolver declined, asked of the resolver",
    .tags(.subprocess),
    .enabled(
        if: ProcessInfo.processInfo.environment["SWIFT_INFER_GENERATOR_CENSUS"] != nil,
        "opt-in census; set SWIFT_INFER_GENERATOR_CENSUS=<corpus path>"
    )
)
struct GeneratorBlockerCensusMeasuredTests {

    @Test("every type the scan knows, attributed by the resolver")
    func attributeEveryDeclinedType() throws {
        let root = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SWIFT_INFER_GENERATOR_CENSUS"]!
        )
        let artifacts = try TemplateRegistry.discoverArtifacts(in: root)
        let shapes = TypeShapeBuilder.shapes(from: artifacts.typeDecls)
        let resolver = GeneratorResolver(types: shapes)
        let byName = Dictionary(shapes.map { ($0.name, $0) }) { first, _ in first }

        var labels: [String: String] = [:]
        var reasons: [String: String] = [:]
        for shape in shapes where !Self.isBuildable(shape.name, resolver: resolver) {
            let failure = resolver.resolutionFailure(forTypeName: shape.name)
            labels[shape.name] = Self.label(for: failure, kind: shape.kind)
            reasons[shape.name] = Self.verbatim(failure)
        }

        Self.report(labels: labels, reasons: reasons, total: shapes.count)
        Self.reportBlame(declined: Set(labels.keys), byName: byName)
        Self.reportSelfSpelling(declined: Set(labels.keys), byName: byName, reasons: reasons)
        // The instrument, not the answer: a run that attributes nothing has measured nothing.
        #expect(!shapes.isEmpty, "the corpus resolved no type shapes at all")
    }

    /// The bucket a declined type lands in: the resolver's failure case, and for `.noStrategy`
    /// the declared kind plus the sentence shape of the strategist's reason.
    ///
    /// ⚠ **`nil` gets its own visible bucket rather than being folded into a neighbour.** It means
    /// the resolver built a generator while `defaultGenerator` still emitted the `.todo` marker —
    /// the two halves of the chain disagreeing — and hiding that is how the first regex attempt
    /// produced a number that looked complete and was not.
    static func label(for failure: ResolutionFailure?, kind: TypeShape.Kind) -> String {
        switch failure {
        case .none:
            return "NO FAILURE RECORDED — the resolver built it and the emitter still declined"

        case .notInUniverse:
            return "not in the universe the resolver was built over"

        case .ambiguous:
            return "ambiguous — two or more types share the name"

        case .aliasUnresolved:
            return "typealias whose underlying spelling does not resolve"

        case .unterminatedRecursion:
            return "recursion with nothing to terminate it"

        case .noStrategy(let reason):
            return "\(kind.rawValue): \(sentenceShape(of: reason))"
        }
    }

    /// The failure as the resolver states it, for a reader checking a bucket rather than counting
    /// it. A sentence shape with its names replaced by `…` is right for counting and useless for
    /// reading — asked the first time the shapes were shown.
    static func verbatim(_ failure: ResolutionFailure?) -> String {
        guard let failure else { return "no failure recorded" }
        if case .noStrategy(let reason) = failure { return reason }
        return "\(failure)"
    }

    /// A `.todo` reason with every backticked name replaced by `…`, so reasons that differ only
    /// in the types and members they name share a bucket.
    static func sentenceShape(of reason: String) -> String {
        reason.replacingOccurrences(of: #"`[^`]*`"#, with: "`…`", options: .regularExpression)
    }

    /// Can the emitter build a value of this type — through the WHOLE chain it actually uses?
    ///
    /// ⚠ **Asking `GeneratorResolver` alone is half the question, and the first run of this probe
    /// got it wrong**: the resolver answers for PROJECT types, so `String`, `Int`, `Bool` and
    /// `Set` came back `nil` and were reported as blockers. The accept path asks the project-type
    /// resolver first and falls through to `defaultGenerator`, which covers `RawType`, the kit's
    /// composed generators, and only then emits the `.todo` marker. A type is unbuildable when
    /// both give up.
    static func isBuildable(_ typeName: String, resolver: GeneratorResolver) -> Bool {
        if resolver.customTypeGenerator(forTypeName: typeName) != nil { return true }
        return !LiftedTestEmitter.defaultGenerator(for: typeName)
            .contains(LiftedTestEmitter.todoGeneratorMarker)
    }

    static func report(labels: [String: String], reasons: [String: String], total: Int) {
        print("type shapes scanned: \(total)")
        print("no generator:        \(labels.count)")
        var counts: [String: Int] = [:]
        for label in labels.values { counts[label, default: 0] += 1 }
        for (label, count) in counts.sorted(by: { $0.value > $1.value }) {
            print(String(format: "  %5d  %@", count, label))
        }
        print("\nexamples per bucket, as the resolver states them:")
        var shown: [String: Int] = [:]
        for (name, label) in labels.sorted(by: { $0.key < $1.key }) where shown[label, default: 0] < 3 {
            shown[label, default: 0] += 1
            print("  \(name): \(reasons[name] ?? label)")
        }
    }

    /// Which unbuildable types stand in the way of others, read off the SHAPE's three edges — a
    /// structural question the resolver's per-type reason does not aggregate.
    static func reportBlame(declined: Set<String>, byName: [String: TypeShape]) {
        var counts: [String: Int] = [:]
        for name in declined {
            guard let shape = byName[name] else { continue }
            let blockers = referencedTypeNames(of: shape)
                .filter { $0 != name && byName[$0] != nil && declined.contains($0) }
            for blocker in blockers { counts[blocker, default: 0] += 1 }
        }
        print("\ntypes that BLOCK the most others:")
        for (name, count) in counts.sorted(by: { $0.value > $1.value }).prefix(20) {
            print(String(format: "  %5d  %@", count, name))
        }
    }

    /// Declined types whose OWN edges spell `Self` — `case array([Self])`, `let next: Self?`.
    ///
    /// Nothing rewrites `Self` to the declaring type: `TypeShapeBuilder.resolvedSpelling` resolves
    /// nested names against the enclosing scope and has no arm for it, and the kit's resolver looks
    /// the spelling up by name. So a recursive payload written `[Self]` reaches the resolver as a
    /// type called `Self`, which nothing declares — before its recursion handling, which a
    /// collection-terminated payload is exactly the shape for, can run. Counted structurally so
    /// the size does not rest on one example.
    static func reportSelfSpelling(
        declined: Set<String>,
        byName: [String: TypeShape],
        reasons: [String: String]
    ) {
        let spelled = declined
            .filter { name in byName[name].map { referencedTypeNames(of: $0).contains("Self") } ?? false }
            .sorted()
        let blamed = spelled.filter { reasons[$0]?.contains("`Self`") == true }
        print("\ndeclined types whose own edges spell `Self`: \(spelled.count)")
        print("  … and whose reason names `Self` as what failed: \(blamed.count)")
        for name in spelled.prefix(10) {
            print("  \(name): \(reasons[name] ?? "")")
        }
    }

    /// The three edges a generator traverses, read off the SHAPE — the same three
    /// `VerifyImportSet.referencedTypeTexts` walks. A shape records stored members only, so a
    /// computed property cannot leak in the way it did through the regex attempt.
    static func referencedTypeNames(of shape: TypeShape) -> Set<String> {
        let texts = shape.storedMembers.map(\.typeName)
            + shape.initializers.flatMap { $0.parameters.map(\.typeName) }
            + shape.enumCases.flatMap { $0.associatedValues.map(\.typeName) }
        var names: Set<String> = []
        for text in texts {
            names.formUnion(VerifyImportSet.identifiers(in: text))
        }
        return names
    }
}
