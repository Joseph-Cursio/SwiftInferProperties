import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// The shapes no scaffold can compile for: each prints one line in its place, naming the obstacle.
extension DiscoverReferenceOracleTests {

    static let declineMarker = "    ── no runnable reference oracle: "

    /// The one decline line in an entry, without its marker, or `nil`.
    static func decline(_ displayName: String) throws -> String? {
        let entry = try scaffold(displayName)
        #expect(
            entry.contains("runnable reference oracle (fill the stub") == false, "\(displayName) printed a scaffold"
        )
        let line = entry.split(separator: "\n").first { $0.hasPrefix(declineMarker) }
        return line.map { String($0.dropFirst(declineMarker.count)) }
    }

    @Test func aPrivateMemberNamesItsRemedy() throws {
        let reason = try #require(try Self.decline("label(_:)"))
        #expect(reason == "`Labels.label(_:)` cannot be called from a test: "
            + AccessRestriction.notVisibleToTests.remedy)
    }

    @Test func aMemberOfAnUnmarkedExtensionOfAPrivateTypeCannotBeNamed() throws {
        let reason = try #require(try Self.decline("doubled(_:)"))
        #expect(reason.hasPrefix(
            "`Vault.doubled(_:)` cannot be called from a test: it names `Vault`, which is `private`"
        ))
    }

    @Test func aGenericFunctionDeclines() throws {
        let reason = try #require(try Self.decline("smallest(_:)"))
        #expect(reason == "smallest(_:) takes T, which is a generic parameter of the function itself and names no "
            + "type at the call site")
    }

    @Test func anInoutParameterDeclines() throws {
        let reason = try #require(try Self.decline("advance(_:)"))
        #expect(reason.contains("takes an `inout` parameter"))
    }

    @Test func aClosureParameterDeclinesAsFunctionTyped() throws {
        let reason = try #require(try Self.decline("twice(_:to:)"))
        #expect(reason == "Apply.twice(_:to:) takes a function-typed parameter (`(Int) -> Int`), and no generator "
            + "draws a function")
    }

    @Test func aResultWithNoEquatableDeclines() throws {
        let reason = try #require(try Self.decline("report(for:)"))
        #expect(reason == "report(for:) returns Report, and no scanned declaration makes Report Equatable, so `==` "
            + "cannot compare two results")
    }

    @Test func anExistentialParameterDeclinesNamingTheType() throws {
        let reason = try #require(try Self.decline("doubledArea(of:)"))
        #expect(reason.hasPrefix("no generator derives for `any Shape` ("))
        #expect(reason.contains("so the oracle cannot draw its `of:` argument"))
    }

    /// The decline names the type the draw stops at — the element nothing derives, not the array
    /// the resolver would compose over it.
    @Test func anUnderivedElementIsNamedRatherThanItsArray() throws {
        let reason = try #require(try Self.decline("tally(_:)"))
        #expect(reason.hasPrefix("no generator derives for `Handle` ("))
        #expect(reason.hasSuffix(
            "so the oracle cannot draw its `_ handles:` argument — supply `static func gen()` on `Handle`, then re-run "
                + "discover"
        ))
    }

    /// A `Void` function printed no scaffold before and prints no decline now: its entry is the
    /// text f87bb241 rendered, byte for byte, with the fixture's directory masked.
    @Test func aVoidFunctionRendersExactlyAsBefore() throws {
        let entry = Self.entry("record(_:)", in: try Self.advice().text)
        let masked = entry.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            guard let range = line.range(of: "/Source.swift:") else { return String(line) }
            return "    <FIXTURE>" + line[range.lowerBound...]
        }
        #expect(masked.joined(separator: "\n") == """
              • record(_:)  (String) -> Void
                <FIXTURE>/Source.swift:79
                the templates could offer only a determinism tautology here (f(x) == f(x), which no wrong \
            code fails). Your docstring is the one refutable contract on this function:
                  "Records the message in the shared log, exactly once."
                encode THAT sentence; it is the law the templates could not name.

            """)
    }
}
