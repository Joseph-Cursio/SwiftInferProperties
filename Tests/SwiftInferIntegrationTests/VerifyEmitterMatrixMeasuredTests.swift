import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// The verify-emitter compile+run matrix — a generative guard for the whole stub
/// emitter, born from the Epic-2 investigation.
///
/// The premise: a code generator's real contract is "the code it emits compiles
/// and runs," and the only way to cover that contract is to feed it inputs the
/// *producers* (discovery) don't currently emit. So this test constructs
/// `SemanticIndexEntry` values **directly** — flipping `isInstanceMethod` etc.
/// independent of discovery — and drives each through the real per-entry verify
/// worker (`surveyRecord`: emit → build → run → parse). The property is: **for
/// every supported (template × carrier × call-shape) cell, the emitted stub
/// COMPILES and, on a trivially-correct implementation
/// (`verify-emitter-matrix-corpus`), runs to `measured-bothPass`.**
///
/// This is what pinned the genuine Epic-2 bug: binary-idempotence routed an
/// INSTANCE operator through the static-call shape, emitting
/// `Type.union(x, x)` (a curried-method type error) — the `binary-idempotence /
/// instance` cell went `measured-error: build-failed` until it was routed through
/// the receiver shape. (It also *disproved* the first hypothesis — the receiver
/// trampoline `{ $0.union($1) }` compiles fine on concretely-typed generator
/// values; the original failure was the carrier not being `Sendable`.)
///
/// Real `swift build`s over a warm shared workdir — tagged `.subprocess`.
@Suite("Verify emitter — compile+run matrix", .tags(.subprocess))
struct VerifyEmitterMatrixMeasuredTests {

    private typealias Verify = SwiftInferCommand.Verify

    /// One cell of the (template × carrier × call-shape) matrix.
    private struct Cell {
        let name: String
        let template: String
        let typeName: String
        let function: String
        let carrierTypeName: String?
        let typeShape: IndexedTypeShape?
        let isInstanceMethod: Bool
        var isNullary = false
        var returnsSelfType = false
        var isComputedProperty = false
    }

    private static let triShape = IndexedTypeShape(
        name: "Tri",
        kind: .enum,
        inheritedTypes: ["CaseIterable"],
        hasUserGen: false
    )

    /// Free/static call shape over `Int` (a directly-generated carrier).
    private static func staticCell(_ name: String, _ template: String, _ function: String) -> Cell {
        Cell(
            name: "\(name)/static",
            template: template,
            typeName: "FreeOps",
            function: function,
            carrierTypeName: "Int",
            typeShape: nil,
            isInstanceMethod: false
        )
    }

    /// Instance call shape over the `CaseIterable` carrier `Tri`.
    private static func instanceCell(
        _ name: String,
        _ template: String,
        _ function: String,
        nullary: Bool = false,
        returnsSelf: Bool = false,
        computedProperty: Bool = false
    ) -> Cell {
        Cell(
            name: "\(name)/\(computedProperty ? "computed-property" : "instance")",
            template: template,
            typeName: "Tri",
            function: function,
            carrierTypeName: nil,
            typeShape: triShape,
            isInstanceMethod: true,
            isNullary: nullary,
            returnsSelfType: returnsSelf,
            isComputedProperty: computedProperty
        )
    }

    private static let cells: [Cell] = [
        staticCell("commutativity", "commutativity", "maximum(_:_:)"),
        staticCell("associativity", "associativity", "maximum(_:_:)"),
        staticCell("binary-idempotence", "binary-idempotence", "maximum(_:_:)"),
        staticCell("involution", "involution", "negated(_:)"),
        staticCell("idempotence", "idempotence", "absolute(_:)"),
        instanceCell("commutativity", "commutativity", "union(_:)"),
        instanceCell("associativity", "associativity", "union(_:)"),
        // The bug's cell: binary-idempotence on an instance operator.
        instanceCell("binary-idempotence", "binary-idempotence", "union(_:)"),
        instanceCell("involution", "involution", "flipped()", nullary: true, returnsSelf: true),
        // Recall epic #1 — an involution written as a read-only COMPUTED PROPERTY
        // (`value.mirrored.mirrored == value`, no parens).
        instanceCell(
            "involution", "involution", "mirrored",
            nullary: true, returnsSelf: true, computedProperty: true
        ),
        // measure non-negativity — the three shapes it fires on: a 1-parameter
        // free/static measure (`length(value) >= 0`), a 0-parameter measure of
        // `self` as a computed property (`value.size >= 0`), and the same as a
        // nullary method (`value.width() >= 0`).
        staticCell("measure", "measure-non-negativity", "length(_:)"),
        instanceCell("measure", "measure-non-negativity", "size", nullary: true, computedProperty: true),
        instanceCell("measure", "measure-non-negativity", "width()", nullary: true),
        // A TUPLE carrier — `ordered((Int, Int))` sorts the pair (idempotent),
        // generated via the kit's `zip` combinator over the component generators.
        Cell(
            name: "idempotence/tuple",
            template: "idempotence",
            typeName: "FreeOps",
            function: "ordered(_:)",
            carrierTypeName: "(Int, Int)",
            typeShape: nil,
            isInstanceMethod: false
        )
    ]

    @Test("every emitter cell compiles and bothPasses on a correct implementation")
    func matrixCompilesAndPasses() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("verify-emitter-matrix")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "VerifyEmitterMatrixCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )
        let config = Verify.SurveyConfig(
            budget: .small,
            corpusModuleName: "VerifyEmitterMatrixCorpus",
            corpusProductName: "VerifyEmitterMatrixCorpus",
            emitRegression: false,
            allShapes: ["Tri": Self.triShape]
        )

        for (index, cell) in Self.cells.enumerated() {
            let entry = SemanticIndexEntry(
                identityHash: String(format: "0x%016X", index + 1),
                templateName: cell.template,
                typeName: cell.typeName,
                score: 60,
                tier: "Likely",
                primaryFunctionName: cell.function,
                location: "Ops.swift:1",
                firstSeenAt: "2026-07-15T00:00:00Z",
                lastSeenAt: "2026-07-15T00:00:00Z",
                typeShape: cell.typeShape,
                carrierTypeName: cell.carrierTypeName,
                isInstanceMethod: cell.isInstanceMethod,
                isNullary: cell.isNullary,
                returnsSelfType: cell.returnsSelfType,
                isComputedProperty: cell.isComputedProperty
            )
            let record = Verify.surveyRecord(for: entry, packageRoot: root, config: config)
            #expect(
                record.outcome == .measuredBothPass,
                "\(cell.name): expected bothPass, got \(record.outcome.rawValue) — \(record.outcomeDetail ?? "")"
            )
        }
    }

    /// `Tests/Fixtures/verify-emitter-matrix-corpus/`, resolved against `#filePath`.
    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("verify-emitter-matrix-corpus")
    }()
}
