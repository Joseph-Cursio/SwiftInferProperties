import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// **The measured half of the B15a compile-safety guarantee: the generators the
/// catalogue ships must actually COMPILE against the pinned kit.**
///
/// `GeneratorRecipeCompileSafetyTests` (in `SwiftInferCoreTests`) guards the same
/// property *structurally* — it bans the three constructs Walk 6 caught
/// (`Gen.frequency`, the static `Gen.array(of:count:)`, and a carrier `.gen()`).
/// But a structural ban only stops the three regressions we already know about;
/// a *new* broken construct — a fourth API that looks runnable and is not —
/// would sail through the string match and re-inflict the exact toil B15a set
/// out to kill (three cold readers each hand-re-implementing the generator
/// because the shipped one would not build). B15a itself flagged the gap: its
/// end-to-end proof lived in a **manual harness**, run once at release and never
/// again.
///
/// This test is that harness, automated. It takes every `GeneratorRecipe` the
/// `CollisionBias` factories emit, drops each `expression` verbatim into a
/// `PropertyLawKit`-importing source, and runs a real `swift build`. If any
/// recipe references an API the kit does not have — in *any* form, not just the
/// three we hand-listed — the build fails and so does this test, naming the
/// compiler error.
///
/// **Kit faithfulness.** The recipes touch only `Gen`/`Generator` from
/// swift-property-based, which the `.interaction` workdir resolves at
/// `from: "1.0.0"` → **1.2.0**, the exact revision `Package.resolved` pins and
/// the one B15a's harness reproduced ("type 'Gen<Value>' has no member
/// 'array'"). `PropertyLawKit`'s own version is irrelevant here — it merely
/// re-exports `Gen` — so this builds against the same generator surface the
/// tool ships against.
///
/// Real `swift build` (~35s cold) — tagged `.subprocess`.
@Suite("Generator recipes compile against the pinned kit (measured)", .tags(.subprocess))
struct GeneratorRecipeCompileMeasuredTests {

    /// Every recipe the catalogue can hand a reader, built from the same
    /// `CollisionBias` factories `GeneratorRecipeCompileSafetyTests` guards
    /// structurally. Adding a factory here keeps the two tests in lockstep.
    private static let recipes: [(label: String, recipe: GeneratorRecipe)] = [
        ("collidingString", CollisionBias.collidingString(subject: "path")),
        ("carrierState", CollisionBias.carrierState(typeName: "ImmediateChildPredicate")),
        ("outOfRangeIndex", CollisionBias.outOfRangeIndex(subject: "index")),
        ("tiedKeys", CollisionBias.tiedKeys(subject: "key", typeName: "String"))
    ]

    @Test("every shipped generator recipe compiles against the vendored kit")
    func allRecipesCompile() throws {
        let workdir = FileManager.default.temporaryDirectory
            .appendingPathComponent("generator-recipe-compile-measured")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workdir) }

        _ = try VerifierWorkdir.synthesize(
            VerifierWorkdir.Inputs(
                workdir: workdir,
                userPackage: nil,
                stubSource: Self.makeStubSource(),
                mode: .interaction
            )
        )

        let output = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
        #expect(
            output.exitCode == 0,
            """
            A shipped GeneratorRecipe does NOT compile against the pinned kit — \
            the B15a guarantee is broken. swift build stderr:
            \(output.stderr)
            """
        )
    }

    /// A `PropertyLawKit`-importing source that binds each recipe's runnable
    /// text to a `let`, then references them all so the type-checker must
    /// resolve every construct. Each `expression` is dropped verbatim after
    /// `let __recipeN =` — the leading comment lines each recipe carries are
    /// skipped by the parser, which binds to the trailing `Gen` expression.
    private static func makeStubSource() -> String {
        var lines = ["import PropertyLawKit", ""]
        for (index, entry) in recipes.enumerated() {
            lines.append("// \(entry.label)")
            lines.append("let __recipe\(index) =")
            lines.append(entry.recipe.expression)
            lines.append("")
        }
        let refs = recipes.indices
            .map { "type(of: __recipe\($0))" }
            .joined(separator: ", ")
        lines.append("print(\(refs))")
        return lines.joined(separator: "\n") + "\n"
    }
}
