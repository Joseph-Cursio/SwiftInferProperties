import Foundation
import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// **Why can the tool not derive a generator for this type?** — the probe
/// `docs/measurements/missing-generator-census.md` §4 asks for.
///
/// That census measured the population: **1,160 of 2,058 emitted stubs carry at least one
/// `.gen()` the tool could not derive**, over **548 distinct types** whose top ten cover 26%.
/// What it could not say is *why*, and its §3 records the failed attempt — walking each failing
/// struct's stored members with a regex reported `some` and `View` among the blocking leaf
/// types, because `var body: some View` is a computed property, and left 119 structs
/// unexplained.
///
/// **The only authority on what `GeneratorResolver` decided is `GeneratorResolver`**, so this
/// asks it, over the same `TypeShape`s `Discover` builds (`TypeShapeBuilder.shapes(from:)`),
/// through the same public entry point the accept path uses.
///
/// ## What it attributes, and how
///
/// `resolve` returns `nil` down three paths, and reports which nowhere:
///
/// 1. **an ambiguous bare name** — two different types share it, and refusing is deliberate;
/// 2. **no shape** — the type is external, or the scan never saw it;
/// 3. **a failure inside `derive`** — it has a shape and still cannot be built.
///
/// The first two are decidable from the same inputs the resolver was given, so they are
/// computed rather than guessed. For the third, the probe asks the resolver about **each of the
/// type's own member types** — the three edges a generator traverses — and reports the ones
/// that answer `nil`. That is a blocker naming a blocker, not a pattern match over source text.
///
/// ⚠ **A type in the third bucket with no failing member is left as its own outcome**, not
/// folded into a neighbouring one. It means `derive` refused for a reason this probe cannot
/// see, and saying so is the point — an unexplained residue that gets quietly bucketed is how
/// the regex attempt produced a number that looked complete and was not.
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

    /// Why one type has no generator.
    enum Blocker: Equatable {
        case ambiguousBareName(declaredTimes: Int)
        case noShape
        case members([String])
        case deriveRefused(shape: String)
    }

    @Test("every type the scan knows, attributed")
    func attributeEveryDeclinedType() throws {
        let root = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SWIFT_INFER_GENERATOR_CENSUS"]!
        )
        let artifacts = try TemplateRegistry.discoverArtifacts(in: root)
        let shapes = TypeShapeBuilder.shapes(from: artifacts.typeDecls)
        let resolver = GeneratorResolver(types: shapes)

        var declaredTimes: [String: Int] = [:]
        for shape in shapes { declaredTimes[shape.name, default: 0] += 1 }
        let byName = Dictionary(shapes.map { ($0.name, $0) }) { first, _ in first }

        var blockers: [String: Blocker] = [:]
        for shape in shapes where !Self.isBuildable(shape.name, resolver: resolver) {
            blockers[shape.name] = Self.blocker(
                for: shape,
                resolver: resolver,
                declaredTimes: declaredTimes,
                byName: byName
            )
        }

        Self.report(blockers: blockers, total: shapes.count)
        // The instrument, not the answer: a run that attributes nothing has measured nothing.
        #expect(!shapes.isEmpty, "the corpus resolved no type shapes at all")
    }

    /// Ask the resolver, then ask it again about the members, rather than reading source text.
    static func blocker(
        for shape: TypeShape,
        resolver: GeneratorResolver,
        declaredTimes: [String: Int],
        byName: [String: TypeShape]
    ) -> Blocker {
        if let times = declaredTimes[shape.name], times > 1 {
            return .ambiguousBareName(declaredTimes: times)
        }
        guard byName[shape.name] != nil else { return .noShape }
        let failing = referencedTypeNames(of: shape)
            .filter { $0 != shape.name }
            // A name only counts as a blocker if the scan knows it as a type. `identifiers(in:)`
            // over-collects on purpose — `VerifyImportSet` relies on a declaration map to filter,
            // and without one a parameter label like `node` reads as a type.
            .filter { byName[$0] != nil }
            .filter { !isBuildable($0, resolver: resolver) }
            .sorted()
        guard failing.isEmpty else { return .members(failing) }
        // Read off the SHAPE — the same structured record `derive` consumes — rather than the
        // source text. A shape carries stored members, initializers and enum cases and nothing
        // else, so this cannot pick up a computed property the way the regex attempt did.
        return .deriveRefused(shape: describe(shape))
    }

    /// What a shape `derive` refused looks like, in the terms `derive` sees it.
    ///
    /// The first run of this probe left 390 of 404 declines as one undifferentiated bucket. The
    /// split is available without guessing: a shape records its kind, its stored members, its
    /// initializers and its enum cases, and those are exactly what a memberwise strategy needs.
    static func describe(_ shape: TypeShape) -> String {
        let kind = shape.kind.rawValue
        if shape.storedMembers.isEmpty, shape.initializers.isEmpty, shape.enumCases.isEmpty {
            return "\(kind), nothing to build from"
        }
        if kind == "class" || kind == "actor" {
            return "\(kind), no memberwise init"
        }
        if shape.enumCases.isEmpty, shape.storedMembers.isEmpty {
            return "\(kind), initializers only"
        }
        return "\(kind), has members — reason not visible here"
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

    /// The three edges a generator traverses, read off the SHAPE — the same three
    /// `VerifyImportSet.referencedTypeTexts` walks, and the reason a computed property cannot
    /// leak in the way it did through the regex attempt: a shape records stored members only.
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

    static func report(blockers: [String: Blocker], total: Int) {
        print("type shapes scanned: \(total)")
        print("no generator:        \(blockers.count)")
        for (label, count) in tally(blockers).sorted(by: { $0.value > $1.value }) {
            print(String(format: "  %5d  %@", count, label))
        }
        printExamples(blockers)

        print("\ntypes that BLOCK the most others:")
        for (name, count) in blamed(blockers).sorted(by: { $0.value > $1.value }).prefix(20) {
            print(String(format: "  %5d  %@", count, name))
        }
    }

    static func tally(_ blockers: [String: Blocker]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for blocker in blockers.values {
            counts[label(for: blocker), default: 0] += 1
        }
        return counts
    }

    static func label(for blocker: Blocker) -> String {
        switch blocker {
        case .ambiguousBareName:
            return "ambiguous bare name"

        case .noShape:
            return "no shape — external or unscanned"

        case .deriveRefused(let shape):
            return "derive refused — \(shape)"

        case .members:
            return "blocked by a member"
        }
    }

    static func blamed(_ blockers: [String: Blocker]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for case .members(let names) in blockers.values {
            for name in names { counts[name, default: 0] += 1 }
        }
        return counts
    }

    /// A few names per bucket, so a reader can check the attribution rather than trust it.
    static func printExamples(_ blockers: [String: Blocker]) {
        print("\nexamples per bucket:")
        var shown: [String: Int] = [:]
        for (name, blocker) in blockers.sorted(by: { $0.key < $1.key }) {
            guard case .deriveRefused(let shape) = blocker, shown[shape, default: 0] < 4 else {
                continue
            }
            shown[shape, default: 0] += 1
            print("  \(shape): \(name)")
        }
    }
}
