@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// The determinism accept path through `SubjectCallPlan`: what it now declines, and the stub
/// shapes that change because they never compiled.
///
/// Each law is synthesized the way `discover --seeds` synthesizes it, from a summary the scanner
/// produced — so `inout` arrives as the scanner spells it, which no hand-built fixture did.
@Suite("Determinism — the accept path through the shared call plan")
struct DeterminismAcceptPathPlanTests {

    private struct SilentDiagnostics: DiagnosticOutput {
        func writeDiagnostic(_: String) { /* no-op */ }
    }

    static func law(_ source: String, named name: String) throws -> Suggestion {
        let summaries = FunctionScanner.scan(source: source, file: "Tokenizer.swift")
        let summary = try #require(summaries.first { $0.name == name })
        let manifest = SeedManifest(seeds: [
            SeedManifest.Seed(file: "Tokenizer.swift", line: summary.location.line, symbol: name, kind: .pureFunction)
        ])
        let laws = SwiftInferCommand.Discover.synthesizeGenericLaws(
            for: manifest,
            summaries: [summary],
            covered: [],
            diagnostics: SilentDiagnostics()
        )
        return try #require(laws.first { $0.templateName == "determinism" })
    }

    static func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    // MARK: - Declined now, written before

    /// **The latent defect.** The old decline read `inout ` off the rendered signature, which the
    /// scanner never writes, so this stub was emitted as `Tokenizer.consume(value)` with a drawn
    /// `let` — *cannot pass immutable value as inout argument*.
    @Test func aScannedInoutSubjectIsDeclinedByBothSides() throws {
        let law = try Self.law("""
            enum Tokenizer {
                static func consume(_ scanner: inout Scanner) -> Token { fatalError() }
            }
            """, named: "consume")
        #expect(InteractiveTriage.deterministicStub(for: law) == nil)
        let reason = try #require(StubApplicationArity.declineReason(for: law))
        #expect(reason.contains("inout"))
    }

    /// A closure parameter mis-split at its `->` and was written as a generator for `(Int`, or
    /// declined as a label-count mismatch; either way the reader was not told the cause.
    @Test func aFunctionTypedParameterIsNamed() throws {
        let law = try Self.law("""
            enum Filter {
                static func count(where test: (Int) -> Bool) -> Int { 0 }
            }
            """, named: "count")
        #expect(InteractiveTriage.deterministicStub(for: law) == nil)
        let reason = try #require(StubApplicationArity.declineReason(for: law))
        #expect(reason.contains("function-typed parameter (`(Int) -> Bool`)"))
    }

    @Test func aFunctionTypedResultIsDeclined() throws {
        let law = try Self.law("""
            enum Adders {
                static func adder(_ step: Int) -> (Int) -> Int { { $0 + step } }
            }
            """, named: "adder")
        #expect(InteractiveTriage.deterministicStub(for: law) == nil)
        let reason = try #require(StubApplicationArity.declineReason(for: law))
        #expect(reason.contains("returns a function"))
    }

    // MARK: - Written differently, because the old text did not compile

    /// `approximatelyEqual` was called and never declared — *cannot find 'approximatelyEqual' in
    /// scope*. It is appended once, as every other caller of the approximate equality does.
    @Test func aDoubleResultStubDeclaresTheHelperOnce() throws {
        let law = try Self.law("""
            enum Geometry {
                static func scale(_ factor: Double) -> Double { factor * 2 }
            }
            """, named: "scale")
        let stub = try #require(InteractiveTriage.deterministicStub(for: law))
        #expect(stub.contains("approximatelyEqual(Geometry.scale(value), Geometry.scale(value))"))
        #expect(Self.occurrences(of: "private func approximatelyEqual", in: stub) == 1)
    }

    /// The control: a throwing subject compares two `Optional`s strictly, so there is no helper.
    @Test func aThrowingDoubleResultIsComparedStrictlyWithNoHelper() throws {
        let law = try Self.law("""
            enum Geometry {
                static func scale(_ factor: Double) throws -> Double { factor * 2 }
            }
            """, named: "scale")
        let stub = try #require(InteractiveTriage.deterministicStub(for: law))
        #expect(stub.contains("(try? Geometry.scale(value)) == (try? Geometry.scale(value))"))
        #expect(stub.contains("approximatelyEqual") == false)
    }

    /// A test file has no `Self`: `(args: (Self, Self))` and `Self.gen()` could not compile.
    @Test func aSelfParameterIsSpelledAsTheOwner() throws {
        let law = try Self.law("""
            struct Point: Equatable {
                let x: Int
                static func merge(_ lhs: Self, _ rhs: Self) -> Self { lhs }
            }
            """, named: "merge")
        let stub = try #require(InteractiveTriage.deterministicStub(for: law))
        #expect(stub.contains(
            "{ (args: (Point, Point)) in Point.merge(args.0, args.1) == Point.merge(args.0, args.1) }"
        ))
        #expect(stub.contains("Self") == false)
    }

    // MARK: - Unchanged

    /// A value-returning `mutating` method was declined before and still is; only the sentence
    /// is new, and it now says why a drawn receiver cannot be used.
    @Test func aMutatingMethodIsStillDeclined() throws {
        let law = try Self.law("""
            struct Counter {
                mutating func advance(by step: Int) -> Int { step }
            }
            """, named: "advance")
        #expect(InteractiveTriage.deterministicStub(for: law) == nil)
        let reason = try #require(StubApplicationArity.declineReason(for: law))
        #expect(reason.contains("mutating"))
    }
}
