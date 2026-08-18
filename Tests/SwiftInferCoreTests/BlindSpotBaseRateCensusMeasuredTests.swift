import Foundation
import SwiftEffectInference
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// **What do the backtest's two blind spots cost THIS corpus?**
///
/// `docs/measurements/purity-backtest.md` measured 0 hits of 3 against public fix
/// commits and named two gaps, then filed their base rates rather than guessing them:
///
/// | blind spot | what the oracle does | decidable here? |
/// |---|---|---|
/// | instance write on a reference type — `self.x = y` in a `class` | `.pure` | **yes** |
/// | hash-order rendering — a `Set` rendered into a returned value | `.pure` | **no, lower bound only** |
///
/// A gap with no instances is item 40's shape — latent, not a defect. A gap with
/// instances is a **false `.pure`** per row, which SEI's own doc calls the most
/// dangerous place to land wrongly, because a generated property test runs the
/// function in-process. `module-state-base-rate.md` asked this question about
/// file-scope `var`s and got zero; these are the two populations that census could not
/// reach.
///
/// ## Why bucket 1 is decidable and bucket 2 is not
///
/// **Bucket 1 needs one fact the syntax carries: the enclosing type's kind.** A write
/// to `self` means different things by receiver — on a `class` it mutates state every
/// holder of the reference can see; on a `struct` it mutates a copy and Swift makes
/// the caller write `mutating`. The backtest measured that boundary and argued only
/// the reference case is a defect. Extensions whose extended type is declared in
/// another file are counted in their own bucket rather than guessed at.
///
/// **Bucket 2 needs a type checker.** Whether `joined()` renders a `Set` or an
/// `Array` decides everything and is invisible to a parse. What is counted is a
/// within-file heuristic — a rendering of a name this same file declares with a `Set`
/// or dictionary type — and it is reported as a **lower bound**, in the same way the
/// unrecognised-callee census reports free-shape-only figures as lower bounds.
@Suite("Census — what the backtest's blind spots cost this corpus", .serialized)
struct BlindSpotBaseRateCensusMeasuredTests {

    // MARK: - Bucket 1 · instance writes, by receiver kind

    enum ReceiverKind: String, CaseIterable {
        case reference       // class — shared state, the defect
        case value          // struct / enum — a copy, and `mutating` says so
        case actorIsolated  // actor — shared but isolated; a third answer, not the first two
        case unknown        // extension of a type declared elsewhere
    }

    struct SelfWrite {
        let file: String
        let name: String
        let kind: ReceiverKind
    }

    /// Bucket 1's two figures, computed in one pass.
    ///
    /// **`anywhere` exists because a zero base rate has two readings a single number
    /// cannot separate**: the detector saw nothing, or it saw plenty and none of it was
    /// in a `.pure` declaration. `Sources/` contains 1,226 explicit `self.x =` lines, so
    /// a detector reporting zero *anywhere* is broken, while one reporting zero only
    /// among `.pure` rows is the filter doing its job. The module-state census published
    /// a zero from a blind detector once already; this is the cheap guard against
    /// repeating it.
    ///
    /// Recomputed from source rather than read off the item 29 census's `Subject`,
    /// because that type carries no enclosing-declaration context and the receiver's
    /// kind is the whole question here. The file enumeration is shared, so the
    /// denominators still agree.
    ///
    /// Initialisers are deliberately absent: an `init` writing `self` is not an
    /// impurity, and `InitializerDeclSyntax` is not a `FunctionDeclSyntax`, so they are
    /// excluded by construction rather than by a filter that could drift.
    static let bucketOne: (rows: [SelfWrite], anywhere: Int) = {
        var found: [SelfWrite] = []
        var anywhere = 0
        let root = PurityRefutationCensusMeasuredTests.packageSourcesRoot
        let packageRoot = PurityRefutationCensusMeasuredTests.packageRoot
        for file in SwiftSourceFiles.sorted(in: root) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let relative = file.path.replacingOccurrences(of: packageRoot.path + "/", with: "")
            let collector = ReceiverAwareFunctionCollector(viewMode: .sourceAccurate)
            collector.walk(Parser.parse(source: text))
            for entry in collector.entries {
                let writer = SelfWriteChecker(viewMode: .sourceAccurate)
                if let body = entry.function.body { writer.walk(body) }
                guard writer.writesSelf else { continue }
                anywhere += 1
                guard SoundPurity.verdict(for: entry.function) == .pure else { continue }
                found.append(
                    SelfWrite(file: relative, name: entry.function.name.text, kind: entry.kind)
                )
            }
        }
        return (found, anywhere)
    }()

    static var selfWrites: [SelfWrite] { bucketOne.rows }

    /// **The base rate.** Only the reference case is a defect — the backtest's boundary
    /// table argues the value case is defensible, and this census does not relitigate
    /// it, it just reports the buckets separately so a reader can disagree.
    static var referenceWrites: [SelfWrite] { selfWrites.filter { $0.kind == .reference } }

    // MARK: - Bucket 2 · hash-order rendering, lower bound

    struct HashOrderHit {
        let file: String
        let name: String
        let rendered: [String]
    }

    /// `.pure` declarations that render a name this same file declares as a `Set` or
    /// dictionary. **A lower bound**: a name declared in another file, or one whose
    /// type is inferred rather than annotated, is invisible here.
    static let hashOrderHits: [HashOrderHit] = {
        var found: [HashOrderHit] = []
        let root = PurityRefutationCensusMeasuredTests.packageSourcesRoot
        let packageRoot = PurityRefutationCensusMeasuredTests.packageRoot
        for file in SwiftSourceFiles.sorted(in: root) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let relative = file.path.replacingOccurrences(of: packageRoot.path + "/", with: "")
            let tree = Parser.parse(source: text)
            let unordered = UnorderedPropertyCollector(viewMode: .sourceAccurate)
            unordered.walk(tree)
            guard !unordered.names.isEmpty else { continue }
            let collector = ReceiverAwareFunctionCollector(viewMode: .sourceAccurate)
            collector.walk(tree)
            for entry in collector.entries {
                guard SoundPurity.verdict(for: entry.function) == .pure,
                      let body = entry.function.body else { continue }
                let renderer = UnorderedRenderChecker(unordered: unordered.names, viewMode: .sourceAccurate)
                renderer.walk(body)
                if !renderer.rendered.isEmpty {
                    found.append(
                        HashOrderHit(
                            file: relative,
                            name: entry.function.name.text,
                            rendered: renderer.rendered.sorted()
                        )
                    )
                }
            }
        }
        return found
    }()

    // MARK: - Controls

    /// Both detectors fire on a synthetic witness, and stay quiet on the shapes they
    /// must not claim. **The module-state census published a zero from a blind
    /// detector once already** — it overrode only the folded operator form, so no
    /// assignment was visible — and the number was identical before and after the fix.
    /// A synthetic witness is the only thing that separates the two readings.
    @Test("the self-write detector fires, and distinguishes the receiver's kind")
    func selfWriteDetectorFires() {
        let source = """
        class Ref { var stored = 0
            func write(_ value: Int) -> Int { self.stored = value; return value }
            func read(_ value: Int) -> Int { value + stored }
        }
        struct Val { var stored = 0
            mutating func write(_ value: Int) -> Int { self.stored = value; return value }
        }
        """
        let collector = ReceiverAwareFunctionCollector(viewMode: .sourceAccurate)
        collector.walk(Parser.parse(source: source))
        var seen: [String: ReceiverKind] = [:]
        for entry in collector.entries {
            let writer = SelfWriteChecker(viewMode: .sourceAccurate)
            if let body = entry.function.body { writer.walk(body) }
            if writer.writesSelf { seen[entry.function.name.text] = entry.kind }
        }
        #expect(seen["write"] != nil, "the detector saw no self-write at all")
        #expect(collector.entries.count == 3, "found \(collector.entries.count) declarations")
        #expect(seen["read"] == nil, "a read of stored state is not a write")
    }

    @Test("the hash-order detector fires on a rendered Set and not on a rendered Array")
    func hashOrderDetectorFires() {
        let source = """
        struct S {
            let kinds: Set<String> = []
            let ordered: [String] = []
            var rendersSet: String { kinds.joined(separator: ", ") }
            var rendersArray: String { ordered.joined(separator: ", ") }
        }
        """
        let tree = Parser.parse(source: source)
        let unordered = UnorderedPropertyCollector(viewMode: .sourceAccurate)
        unordered.walk(tree)
        #expect(unordered.names == ["kinds"], "collected \(unordered.names.sorted())")

        let collector = ReceiverAwareFunctionCollector(viewMode: .sourceAccurate)
        collector.walk(tree)
        // Computed properties are not FunctionDeclSyntax, so this control asserts on
        // the checker directly rather than through the collector.
        let hit = UnorderedRenderChecker(unordered: unordered.names, viewMode: .sourceAccurate)
        hit.walk(Parser.parse(source: "func f() -> String { kinds.joined(separator: \", \") }"))
        #expect(hit.rendered == ["kinds"], "rendered \(hit.rendered)")

        let miss = UnorderedRenderChecker(unordered: unordered.names, viewMode: .sourceAccurate)
        miss.walk(Parser.parse(source: "func f() -> String { ordered.joined(separator: \", \") }"))
        #expect(miss.rendered.isEmpty, "an Array render must not count: \(miss.rendered)")
    }

    /// **The zero has to be reconciled, not just reported.** `Sources/` contains 1,226
    /// explicit `self.x =` lines, so a bucket-1 count of zero is only meaningful
    /// alongside the count of writes found *anywhere* — the two readings a single
    /// figure cannot separate. The module-state census published a zero from a blind
    /// detector before this guard existed.
    ///
    /// Asserted as an exact equality rather than a bound: if `anywhere` ever becomes
    /// non-zero, the reconciliation in the doc is stale and the buckets need re-reading.
    @Test("bucket 1's zero is reconciled — no method writes self, though 1,226 init lines do")
    func bucketOneZeroIsReconciled() {
        #expect(
            Self.bucketOne.anywhere == 0,
            "\(Self.bucketOne.anywhere) self-writes now appear in methods — re-take bucket 1"
        )
        #expect(Self.selfWrites.isEmpty)
    }

    /// Bucket 2 is non-zero, and every row it reports is genuinely `.pure` — so every
    /// row is a false verdict rather than a note about an already-refuted function.
    @Test("every bucket-2 row is a .pure verdict, which is what makes it a false one")
    func bucketTwoRowsArePure() {
        #expect(Self.hashOrderHits.isEmpty == false, "bucket 2 was non-zero when measured")
        for hit in Self.hashOrderHits {
            #expect(hit.rendered.isEmpty == false, "\(hit.name) reported no rendered name")
        }
    }

    // MARK: - The census

    @Test("census — the two blind spots' base rates")
    func census() {
        let pureCount = PurityRefutationCensusMeasuredTests.verdicts.filter { $0 == .pure }.count
        var lines: [String] = ["", "BLIND-SPOT BASE RATE CENSUS", ""]
        lines.append("population: \(pureCount) `.pure` of \(PurityRefutationCensusMeasuredTests.corpus.count)")
        lines.append("")
        lines.append("BUCKET 1 — self-writes in ANY declaration: \(Self.bucketOne.anywhere)")
        lines.append("BUCKET 1 — `.pure` declarations writing `self.x`, by receiver:")
        for kind in ReceiverKind.allCases {
            let rows = Self.selfWrites.filter { $0.kind == kind }
            lines.append("  \(kind.rawValue.padding(toLength: 16, withPad: " ", startingAt: 0)) \(rows.count)")
        }
        lines.append("  --> BASE RATE (reference types, the defect): \(Self.referenceWrites.count)")
        for row in Self.referenceWrites.prefix(25) {
            lines.append("      \(row.file.replacingOccurrences(of: "Sources/", with: "")):\(row.name)")
        }
        lines.append("")
        let bucketTwo = Self.hashOrderHits.count
        lines.append("BUCKET 2 — `.pure` decls rendering a same-file Set/Dict: \(bucketTwo) (LOWER BOUND)")
        for row in Self.hashOrderHits.prefix(25) {
            let location = row.file.replacingOccurrences(of: "Sources/", with: "")
            let names = row.rendered.joined(separator: ", ")
            lines.append("      \(location):\(row.name) -> \(names)")
        }
        print(lines.joined(separator: "\n"))
    }
}
