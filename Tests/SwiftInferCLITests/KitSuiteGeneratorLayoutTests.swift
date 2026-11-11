import Foundation
import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// **Where a multi-line kit generator lands in a `scaffold-kit-suites` file.** Swift's
/// multi-line literal does not re-indent interpolated text, so `liveBlock` places the kit's
/// expression itself (`KitSuiteEmitter.placedUnderUsing`), anchoring its closing line under
/// `using:`. The anchor has to hold for the kit this package resolves today, which bakes a
/// memberwise `.map` at column 12, and for the kit's `ExpressionLayout` rule, which puts it at 0.
@Suite("Kit-suite generator layout")
struct KitSuiteGeneratorLayoutTests {

    private func finding(_ typeName: String, conformance: String) -> ProtocolCoverageAudit.Finding {
        ProtocolCoverageAudit.Finding(
            typeName: typeName,
            coveringConformance: conformance,
            standing: .assumed,
            coveredLaws: [.equatableReflexive],
            declaredCoveringConformances: [conformance]
        )
    }

    /// **A memberwise generator's `.map` lines up under `using:`, whichever kit resolves.**
    /// The kit's `zip(...)` / `.map { ... }` spans two lines. Through SwiftPropertyLaws 4.11
    /// its `.map` came baked at column 12; under the kit's `ExpressionLayout` rule it comes at
    /// column 0, and spliced unchanged it landed at the left margin of the suite.
    @Test("a two-member generator's .map sits under using:")
    func memberwiseMapSitsUnderUsing() {
        let point = TypeShape(
            name: "Point", kind: .struct, inheritedTypes: ["Equatable"], hasUserGen: false,
            storedMembers: [StoredMember(name: "x", typeName: "Int"), StoredMember(name: "y", typeName: "Int")]
        )
        let emission = KitSuiteEmitter.emit(
            findings: [finding("Point", conformance: "Equatable")],
            shapes: ["Point": point],
            moduleName: "M"
        )
        let lines = emission.source.components(separatedBy: "\n")
        let using = lines.first { $0.contains("using: zip(") }
        let map = lines.first { $0.contains(".map { Point(") }
        #expect(using != nil && map != nil, "the generator spans two lines")
        let indent = { (line: String?) in line?.prefix { $0 == " " }.count }
        #expect(indent(map) == indent(using))
    }

    /// **A `Gen.oneOf(` list closes under `using:`, whichever kit resolves.** Both kits render
    /// an enum's case list with its `)` at column 0, so spliced unchanged it landed at the
    /// suite's left margin. Unlike the memberwise test above, this one fails against today's
    /// kit too if `liveBlock` stops placing the generator.
    @Test("an enum's oneOf list closes under using:")
    func oneOfClosesUnderUsing() {
        let mode = TypeShape(
            name: "Mode", kind: .enum, inheritedTypes: ["Equatable"], hasUserGen: false,
            storedMembers: [], enumCases: [EnumCase(name: "on"), EnumCase(name: "off")]
        )
        let emission = KitSuiteEmitter.emit(
            findings: [finding("Mode", conformance: "Equatable")],
            shapes: ["Mode": mode],
            moduleName: "M"
        )
        let lines = emission.source.components(separatedBy: "\n")
        let indent = { (line: String) in line.prefix { $0 == " " }.count }
        guard let usingIndex = lines.firstIndex(where: { $0.contains("using: Gen.oneOf(") }),
              let closing = lines[(usingIndex + 1)...].first(where: {
                  $0.trimmingCharacters(in: .whitespaces).hasPrefix(")")
              })
        else {
            Issue.record("expected a multi-line Gen.oneOf generator")
            return
        }
        #expect(indent(closing) == indent(lines[usingIndex]))
        #expect(indent(lines[usingIndex + 1]) == indent(lines[usingIndex]) + 4)
    }

    /// The old kit's text, with its `.map` already at 12, does not move.
    @Test("a closing line already at column 12 stays put")
    func bakedTwelveIsUnchanged() {
        let old = "zip(Gen<Int>.int(), Gen<Int>.int())\n            .map { P(x: $0.0, y: $0.1) }"
        #expect(KitSuiteEmitter.placedUnderUsing(old) == old)
    }

    /// The new kit's text, relative to its own first line, moves 12 as a whole, so a
    /// `Gen.oneOf(` member keeps its cases 4 deeper than its `)`.
    @Test("an expression closing at column 0 moves 12 as a whole")
    func relativeExpressionMovesTwelve() {
        let relative = "zip(Gen<Int>.int(), Gen.oneOf(\n    Gen.always(M.a).eraseToAny()\n))\n"
            + ".map { P(n: $0.0, m: $0.1) }"
        let placed = "zip(Gen<Int>.int(), Gen.oneOf(\n                Gen.always(M.a).eraseToAny()\n            ))\n"
            + "            .map { P(n: $0.0, m: $0.1) }"
        #expect(KitSuiteEmitter.placedUnderUsing(relative) == placed)
    }

    @Test("a single-line generator is unchanged")
    func singleLineIsUnchanged() {
        #expect(KitSuiteEmitter.placedUnderUsing("Gen<Int>.int()") == "Gen<Int>.int()")
    }
}
