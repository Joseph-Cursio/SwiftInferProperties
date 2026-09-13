import Foundation
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// **S3 is the stage that decides the corpus walk, and nothing has ever been built for it.**
///
/// `roadtest-swiftmarkdownwiki.md` attributes 19 rows to S3 — a law a reader wrote by hand that
/// no template names — against 3 for S5 and 4 for S6. Eleven filings have shipped and every one
/// is plumbing between the catalog and the compiler. One S3 row has closed, and it closed by
/// accident: `guard-domain` (#443) was built to emit characterisation tests and turned out to
/// state P1 verbatim.
///
/// **This census sizes the candidate shapes before one is chosen**, because "covers the most
/// rows" is the wrong question alone — a shape covering four rows of one subject and occurring
/// nowhere else is a worse investment than one covering two rows and thousands of functions.
///
/// **And a raw population is the wrong number too.** #437 measured what an ungated shape costs:
/// a gate admitting 92% floods the reader with narration instead of findings. So each shape is
/// counted twice where a gate exists — raw, and through the gate that would actually fire.
///
/// ⚠ **Every count is a FLOOR.** The scan is syntactic and per-function: it resolves no types,
/// reads no docstring, and cannot see a returned type's stored properties. Under-counting makes
/// a shape look like a worse investment, which is the safe direction for this decision.
@Suite("Census — what shapes would close S3?", .serialized)
struct S3ShapeCensusMeasuredTests {

    static let excludedDirectories = [".build", ".git", "checkouts", ".swiftinfer"]

    /// Verbs whose guarantee is a *removal*: the result is built by taking things out of the
    /// input, so it is a subsequence of it. Drawn from the walk's own subjects rather than
    /// invented.
    static let removalVerbs = [
        "strip", "stripping", "stripped", "trim", "trimmed", "trimming",
        "drop", "dropping", "remove", "removing", "removed", "deleting",
        "sanitize", "sanitized", "filtered", "filtering", "excluding", "without"
    ]

    /// Names that denote a measure — a count, an offset, an extent. A measure is non-negative,
    /// which is `T1`/`T2` stated over a *field* of a returned struct rather than the return.
    static let measureNames = ["length", "count", "location", "size", "distance", "offset", "index"]

    /// Roles whose postcondition is **closed under reapplication**: the output satisfies it, and
    /// the function is the identity on inputs that already do. For these, idempotence and
    /// fixpoint are statements about the role rather than about the signature.
    ///
    /// `escaped` / `unescaped` are excluded deliberately — escaping twice double-escapes, so the
    /// postcondition is emphatically not closed. `reversed` / `shuffled` are excluded because
    /// their postconditions are about cardinality, which reapplying does not preserve as identity.
    static let closedRoles: Set<RolePostcondition> = [
        .sorted, .clamped, .rounded, .lowercased, .uppercased, .deduplicated
    ]

    struct Shape {
        let key: String
        let rows: String
        var hits = 0
        var examples: [String] = []

        mutating func record(_ example: @autoclosure () -> String) {
            hits += 1
            if examples.count < 4 { examples.append(example()) }
        }
    }

    struct Tally {
        var parameterised = Shape(key: "A  · parameterised idempotence (T, P…) -> T", rows: "T4")
        var gatedA = Shape(key: "A' · shape A through the curated verb gate", rows: "T4")
        var removal = Shape(key: "B  · removal verb, (String) -> String", rows: "P2, Q2")
        var measure = Shape(key: "C  · measure-named param, non-numeric return", rows: "T1, T2")
        var closedRole = Shape(key: "D  · role whose postcondition is CLOSED", rows: "T4 + T5")
        var anyRole = Shape(key: "—  reference: any RolePostcondition match", rows: "role-postcondition")
        var unary = Shape(key: "—  control: unary (T) -> T, what idempotence reaches", rows: "—")

        var all: [Shape] { [parameterised, gatedA, removal, measure, closedRole, anyRole, unary] }
    }

    static func isExcluded(_ url: URL) -> Bool {
        url.pathComponents.contains { Self.excludedDirectories.contains($0) }
    }

    private static func bare(_ text: String) -> String {
        var out = text.trimmingCharacters(in: .whitespaces)
        while out.hasSuffix("?") || out.hasSuffix("!") { out.removeLast() }
        return out
    }

    /// Shape A: the subject's type is returned, and something else is held fixed. `clamped(to:)`
    /// is the receiver form — the scan sees one parameter and a `Self` return.
    private static func isParameterised(_ summary: FunctionSummary, returning ret: String) -> Bool {
        let params = summary.parameters
        if let first = params.first, params.count >= 2, bare(first.typeText) == ret { return true }
        let selfReturning = ret == "Self" || ret == summary.containingTypeName
        return selfReturning && !params.isEmpty && !summary.isStatic
    }

    private static func isRemoval(_ summary: FunctionSummary, returning ret: String) -> Bool {
        let params = summary.parameters
        guard ret == "String", params.count == 1, bare(params[0].typeText) == "String" else { return false }
        let lowered = summary.name.lowercased()
        return removalVerbs.contains { lowered.contains($0) }
    }

    private static func hasMeasureParameter(_ summary: FunctionSummary) -> Bool {
        summary.parameters.contains { param in
            let spelling = (param.label ?? param.internalName).lowercased()
            return measureNames.contains { spelling.contains($0) }
        }
    }

    private static func classify(_ summary: FunctionSummary, corpus: String, into tally: inout Tally) {
        guard let returnText = summary.returnTypeText else { return }
        let ret = bare(returnText)
        guard ret != "Void", !ret.isEmpty else { return }
        let params = summary.parameters

        if isParameterised(summary, returning: ret) {
            tally.parameterised.record("\(corpus): \(summary.name) -> \(ret)")
            if IdempotenceTemplate.curatedVerbs.contains(summary.name) {
                tally.gatedA.record("\(corpus): \(summary.name)")
            }
        }
        if isRemoval(summary, returning: ret) {
            tally.removal.record("\(corpus): \(summary.name)")
        }
        if hasMeasureParameter(summary), !["Int", "Bool", "String", "Double"].contains(ret) {
            tally.measure.record("\(corpus): \(summary.name) -> \(ret)")
        }
        if params.count == 1, bare(params[0].typeText) == ret {
            tally.unary.record("\(corpus): \(summary.name)")
        }
        if let role = RolePostcondition.matches(name: summary.name, parameterLabels: params.map(\.label)) {
            tally.anyRole.record("\(corpus): \(summary.name)")
            if closedRoles.contains(role) {
                tally.closedRole.record("\(corpus): \(summary.name) [\(role.rawValue)]")
            }
        }
    }

    @Test("size each candidate S3 shape across the manifest corpora")
    func censusCandidateShapes() {
        var tally = Tally()
        var totalFunctions = 0
        var scanned: [String] = []

        for corpus in CorpusManifest.available {
            scanned.append(corpus.id)
            let files = FileManager.default
                .enumerator(at: corpus.primaryRoot, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" && !Self.isExcluded($0) } ?? []
            for file in files {
                guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
                for summary in FunctionScanner.scanCorpus(source: source, file: file.lastPathComponent).summaries {
                    totalFunctions += 1
                    Self.classify(summary, corpus: corpus.id, into: &tally)
                }
            }
        }

        print("\n=== S3 CANDIDATE SHAPE CENSUS ===")
        print("corpora scanned: \(scanned.count) — \(scanned.joined(separator: ", "))")
        print("absent from this machine: \(CorpusManifest.absent.joined(separator: ", "))")
        print("functions scanned: \(totalFunctions)\n")
        for shape in tally.all {
            let share = totalFunctions == 0 ? 0.0 : Double(shape.hits) / Double(totalFunctions) * 100
            let key = shape.key.padding(toLength: max(shape.key.count, 48), withPad: " ", startingAt: 0)
            print("\(key) \(shape.hits)  (\(String(format: "%.2f", share))%)  rows: \(shape.rows)")
            for example in shape.examples { print("      e.g. \(example)") }
        }
        print("=== END CENSUS ===\n")

        // The census exists to be read, not to assert a threshold — a number pinned here would
        // move every time a corpus does. What IS pinned: it looked at something.
        #expect(totalFunctions > 1_000, "a census that scans almost nothing reports a silent zero")
        #expect(CorpusManifest.available.isEmpty == false)
    }
}
