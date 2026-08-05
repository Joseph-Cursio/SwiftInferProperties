@testable import SwiftInferCore
import Testing

/// The return-shape classifier behind `Signal.Kind.returnExtendsInput`.
///
/// Item 18: a 2026-08-04 survey ran every `idempotence` candidate on this repo —
/// **55 executed, 13 refuted, a 24% false-law rate**. This reads the one thing
/// that separates a projection from a construction.
@Suite("IdempotenceReturnShape — does the result grow its input?")
struct IdempotenceReturnShapeTests {

    private func shape(_ source: String) throws -> IdempotenceReturnShape? {
        let summaries = FunctionScanner.scanCorpus(source: source, file: "S.swift").summaries
        return try #require(summaries.first).bodySignals.idempotenceReturnShape
    }

    // MARK: - Extension: the law is false

    @Test("Wrapping in delimiters extends the input")
    func wrappingExtends() throws {
        // `quoted(_:)` in this repo, minus the escaping. Measured refuting.
        let result = try shape("""
        enum H { static func quoted(_ fragment: String) -> String { "\\"\\(fragment)\\"" } }
        """)
        guard case .extendsInput = result else {
            Issue.record("expected .extendsInput, got \(String(describing: result))")
            return
        }
    }

    @Test("appendingPathComponent extends the input")
    func pathExtends() throws {
        // The `defaultPath(for:)` family — nine rows, all measured refuting.
        let result = try shape("""
        import Foundation
        enum H { static func defaultPath(for root: URL) -> URL { root.appendingPathComponent("x") } }
        """)
        guard case .extendsInput = result else {
            Issue.record("expected .extendsInput, got \(String(describing: result))")
            return
        }
    }

    @Test("Concatenation onto the input extends it")
    func concatenationExtends() throws {
        let result = try shape("""
        enum H { static func bump(_ text: String) -> String { text + "." } }
        """)
        guard case .extendsInput = result else {
            Issue.record("expected .extendsInput, got \(String(describing: result))")
            return
        }
    }

    // MARK: - Not extending: the veto must stay quiet

    /// Every one of these MEASURED `bothPass` in the survey. A veto that fired
    /// on any of them would suppress a true law, which is the failure mode that
    /// matters — the rows it wrongly kills are invisible, while the ones it
    /// wrongly spares merely cost a build.
    @Test(
        "Projections are not flagged — the rows that measured bothPass",
        arguments: [
            ("strip at a delimiter", """
            enum H { static func stripGenerics(_ t: String) -> String {
                guard let a = t.firstIndex(of: "<") else { return t }
                return String(t[t.startIndex..<a])
            } }
            """),
            ("replacingOccurrences", """
            enum H { static func slug(_ t: String) -> String { t.replacingOccurrences(of: ".", with: "_") } }
            """),
            ("lowercased", """
            enum H { static func fold(_ t: String) -> String { t.lowercased() } }
            """)
        ]
    )
    func projectionsAreNotFlagged(label: String, source: String) throws {
        #expect(try shape(source) == .notExtending, "false veto on: \(label)")
    }

    /// **Interpolation alone is a conversion, not an extension.** `"\(x)"`
    /// renders a value; it does not grow it. Only interpolation with literal
    /// text around it builds something larger.
    @Test("Bare interpolation is not extension")
    func bareInterpolationIsNotExtension() throws {
        #expect(
            try shape("""
            enum H { static func render(_ t: String) -> String { "\\(t)" } }
            """) == .notExtending
        )
    }

    /// **The narrowing that two measured false vetoes forced.**
    ///
    /// A bare `+` rule vetoed `prioritised` and `unwrappingRepetition`, both of
    /// which measured `bothPass` — they are genuinely idempotent. `+` between two
    /// expressions both derived from the input is a REORDERING, not a growth.
    /// Only a literal operand makes it a construction.
    @Test(
        "Concatenating two input-derived expressions is a reorder, not growth",
        arguments: [
            ("partition then rejoin", """
            enum H { static func prioritised(_ xs: [Int]) -> [Int] {
                xs.filter { $0 > 0 } + xs.filter { $0 <= 0 }
            } }
            """),
            ("splice two derived slices", """
            enum H { static func splice(_ xs: [Int]) -> [Int] {
                Array(xs.dropLast()) + Array(xs.suffix(1))
            } }
            """)
        ]
    )
    func inputDerivedConcatenationIsNotExtension(label: String, source: String) throws {
        #expect(try shape(source) == .notExtending, "false veto on: \(label)")
    }

    /// The other side of that line: a literal operand IS growth.
    @Test("Concatenating a literal extends the input")
    func literalConcatenationExtends() throws {
        let result = try shape("""
        enum H { static func bump(_ xs: [Int]) -> [Int] { xs + [0] } }
        """)
        guard case .extendsInput = result else {
            Issue.record("expected .extendsInput, got \(String(describing: result))")
            return
        }
    }

    // MARK: - Scope

    /// Computed only for a unary endomorphism — the shape the template can
    /// propose for. Paying a body read for every function would buy nothing.
    @Test("Nothing is classified for a non-`T -> T` shape")
    func onlyEndomorphismsAreClassified() throws {
        #expect(try shape("enum H { static func size(_ t: String) -> Int { t.count } }") == nil)
    }

    /// The class this deliberately does NOT claim: **domain transfer**, where
    /// `T -> T` returns a different KIND of thing. Six of the survey's 13
    /// refutations were this, and it is left to `.notExtending` on purpose —
    /// it is not characterised well enough to veto on, and a veto that fires on
    /// a guess suppresses true laws.
    @Test("Domain transfer is NOT claimed — a known, deliberate miss")
    func domainTransferIsNotClaimed() throws {
        #expect(
            try shape("""
            enum H { static func hashOf(_ t: String) -> String { String(t.hashValue, radix: 16) } }
            """) == .notExtending
        )
    }
}
