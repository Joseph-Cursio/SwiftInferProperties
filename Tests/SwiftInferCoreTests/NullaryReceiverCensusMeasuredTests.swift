import Foundation
import SwiftInferCore
import SwiftInferTemplates
import SwiftParser
import SwiftSyntax
import Testing

/// **How many laws are lost because the carrier is read from a parameter that does not exist?**
///
/// #456: `shellEscapeForVariableName() -> Self` is a nullary instance method whose idempotence is
/// `value.f().f() == value.f()` — spellable today, since `CalleeReference.applicationArity` for a
/// nullary instance method is **1**, exactly what `idempotence` applies. It is declined anyway,
/// because `idempotentStub` guards on `paramType(from: evidence.signature)` and a nullary method
/// has no parameter. **The carrier for a receiver-form law is the receiver's type**, a
/// distinction `RoleClosureTemplate.transformedType(of:)` already makes.
///
/// ## Why the census comes first
///
/// This walk has measured an obvious fix as far smaller than it looked three times:
/// parameterised idempotence **1 602 → 6** through its gate, a removal-verb generator **16 in
/// 32 369**, and literal-seeding **4 in 116**. A raw count here is 708, which is exactly the
/// shape of number that has been wrong before.
///
/// ## The three numbers, and only the third is the population
///
/// - **nullary instance methods** — the denominator, and meaningless alone.
/// - **…whose return type is the receiver's** — `f(f(x))` has to typecheck. `renderedLine() ->
///   String` on a non-`String` type composes with nothing.
/// - **…that `IdempotenceTemplate` actually suggests** — what would fire. The gate is the
///   measurement, and it is asked of the template rather than modelled here.
///
/// ⚠ **The first version of this census modelled the gate as the curated verb list and reported
/// 2.** The witness does not carry a curated verb: it fires on `Type-symmetry signature: self ->
/// Self (+30)`, which is a shape signal. Modelling a gate instead of calling it produced a
/// two-order-of-magnitude false decline, caught only by reading the tool's own output for the
/// subject the issue names. Second time in two days a census gate of mine was wrong.
///
/// ⚠ **A floor.** Types are not resolved, so a `Self` return inside a protocol extension and a
/// concrete return that happens to match are counted alike, and a subject reached only through a
/// typealias is missed. Under-counting makes the fix look like a worse investment, which is the
/// safe direction.
@Suite("Census — laws lost to a carrier read from a missing parameter", .serialized)
struct NullaryReceiverCensusMeasuredTests {

    static let excludedDirectories = [".build", ".git", "checkouts", ".swiftinfer"]

    static func isExcluded(_ url: URL) -> Bool {
        url.pathComponents.contains { Self.excludedDirectories.contains($0) }
    }

    struct Tally {
        var nullaryInstance = 0
        var composable = 0
        var gated = 0
        var examples: [String] = []
    }

    private final class Collector: SyntaxVisitor {
        var tally = Tally()
        private var typeStack: [String] = []

        private func enter(_ name: String) -> SyntaxVisitorContinueKind {
            typeStack.append(name)
            return .visitChildren
        }

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { enter(node.name.text) }
        override func visitPost(_: StructDeclSyntax) { typeStack.removeLast() }
        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { enter(node.name.text) }
        override func visitPost(_: ClassDeclSyntax) { typeStack.removeLast() }
        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { enter(node.name.text) }
        override func visitPost(_: EnumDeclSyntax) { typeStack.removeLast() }
        override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
            enter(node.extendedType.trimmedDescription)
        }
        override func visitPost(_: ExtensionDeclSyntax) { typeStack.removeLast() }

        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            let modifiers = node.modifiers.map(\.name.text)
            guard node.signature.parameterClause.parameters.isEmpty,
                  let carrier = typeStack.last,
                  modifiers.contains("static") == false,
                  modifiers.contains("class") == false,
                  node.modifiers.contains(where: { $0.name.text == "mutating" }) == false,
                  let returns = node.signature.returnClause?.type.trimmedDescription
            else { return .visitChildren }
            tally.nullaryInstance += 1

            // `f(f(x))` must typecheck: the result has to be the receiver's own type.
            guard returns == "Self" || returns == carrier else { return .visitChildren }
            tally.composable += 1

            tally.gated += 1
            if tally.examples.count < 10 {
                tally.examples.append("\(carrier).\(node.name.text)() -> \(returns)")
            }
            return .visitChildren
        }
    }

    @Test("size the nullary receiver-form population")
    func censusNullaryReceivers() {
        var total = Tally()
        var scanned: [String] = []
        for corpus in CorpusManifest.available {
            scanned.append(corpus.id)
            let files = FileManager.default
                .enumerator(at: corpus.primaryRoot, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" && !Self.isExcluded($0) } ?? []
            for file in files {
                guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
                let collector = Collector(viewMode: .sourceAccurate)
                collector.walk(Parser.parse(source: source))
                total.nullaryInstance += collector.tally.nullaryInstance
                total.composable += collector.tally.composable
                total.gated += collector.tally.gated
                for example in collector.tally.examples where total.examples.count < 10 {
                    total.examples.append("\(corpus.id): \(example)")
                }
            }
        }

        print("\n=== NULLARY RECEIVER CENSUS (#456) ===")
        print("corpora scanned: \(scanned.count)")
        print("nullary instance methods            : \(total.nullaryInstance)")
        print("…returning the receiver's own type  : \(total.composable)")
        print("(a floor: the real gate is asked of the template below)")
        for example in total.examples { print("    \(example)") }
        print("=== END CENSUS ===\n")

        #expect(total.nullaryInstance > 50, "a census finding almost no denominator reports a silent zero")
    }

    /// **The positive control.** A zero without one is a broken detector and an empty population
    /// reported as the same number — the failure that produced a false decline in the
    /// literal-witness census two days ago. This is #456's witness, reduced.
    @Test func theDetectorFindsTheKnownWitness() {
        let source = """
        extension String {
            func trimmed() -> Self { self }
            func renderedLine() -> Int { 0 }
        }
        """
        let collector = Collector(viewMode: .sourceAccurate)
        collector.walk(Parser.parse(source: source))
        #expect(collector.tally.nullaryInstance == 2, "both are nullary instance methods")
        #expect(collector.tally.composable == 1, "only the `-> Self` one composes")
        #expect(collector.tally.gated == 1, "the composable one is the emittable shape")
    }

    /// The negatives: a static method has no receiver, and a mutating one returns no value the
    /// law can compare.
    @Test func staticAndMutatingAreExcluded() {
        let source = """
        struct Doc {
            static func shared() -> Doc { Doc() }
            mutating func normalized() -> Doc { self }
        }
        """
        let collector = Collector(viewMode: .sourceAccurate)
        collector.walk(Parser.parse(source: source))
        #expect(collector.tally.nullaryInstance == 0)
    }
}

/// The same question asked of the **template itself** rather than of a model of it.
///
/// `FunctionScanner` produces the summaries `TemplateRegistry` sees, and `IdempotenceTemplate`
/// decides. A nullary instance method that it suggests, and that `idempotentStub` then drops
/// because `paramType` finds no parameter, is a law the pipeline proposes and cannot write.
@Suite("Census — laws idempotence proposes and the emitter cannot write", .serialized)
struct NullaryReceiverEmissionLossMeasuredTests {

    @Test("count the laws lost between suggestion and emission")
    func countLostLaws() {
        var suggested = 0
        var nullaryLost = 0
        var examples: [String] = []

        for corpus in CorpusManifest.available {
            let files = FileManager.default
                .enumerator(at: corpus.primaryRoot, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter {
                    $0.pathExtension == "swift"
                        && !NullaryReceiverCensusMeasuredTests.isExcluded($0)
                } ?? []
            for file in files {
                guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
                let scanned = FunctionScanner.scanCorpus(source: source, file: file.lastPathComponent)
                for summary in scanned.summaries {
                    guard IdempotenceTemplate.suggest(for: summary) != nil else { continue }
                    suggested += 1
                    // `idempotentStub` reads its carrier from the first PARAMETER. A nullary
                    // subject has none, so the guard fails and the law is never written.
                    guard summary.parameters.isEmpty else { continue }
                    nullaryLost += 1
                    if examples.count < 8 {
                        examples.append("\(corpus.id): \(summary.containingTypeName ?? "?").\(summary.name)()")
                    }
                }
            }
        }

        let share = suggested == 0 ? 0.0 : Double(nullaryLost) / Double(suggested) * 100
        print("\n=== EMISSION LOSS (#456) ===")
        print("idempotence suggestions      : \(suggested)")
        print("…nullary, so carrier is lost : \(nullaryLost)  (\(String(format: "%.1f", share))%)")
        for example in examples { print("    \(example)") }
        print("=== END ===\n")

        #expect(suggested > 10, "a census finding almost no suggestions reports a silent zero")
    }
}
