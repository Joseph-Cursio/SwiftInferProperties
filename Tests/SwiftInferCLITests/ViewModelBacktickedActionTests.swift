@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// #693: ``func `add`()`` beside `func add(x:)` is one Swift name twice. The recognizer used to store
/// `TokenSyntax.text`, which keeps the backticks, so the emitter compared `` `add` `` with `add` as strings,
/// gave neither an overload suffix, and wrote `case `add`` beside `case add(x: Int)`, which `swiftc` rejects
/// as a redeclaration. `ViewModelActionEnumTypecheckTests` typechecks the emitted source.
@Suite("View model action names — identifiers, not spellings (#693)")
struct ViewModelBacktickedActionTests {

    static let counterSource = """
    import Observation

    @Observable
    final class Counter {
        var count = 0
        func `add`() { count += 1 }
        func add(x: Int) { count += x }
        func `repeat`() { count *= 2 }
    }
    """

    static func counter() throws -> ViewModelCandidate {
        try #require(ViewModelDiscoverer.discover(source: counterSource, file: "Counter.swift").first)
    }

    @Test("the recognizer stores each method's identifier, without backticks")
    func recognizerStripsBackticks() throws {
        #expect(try Self.counter().actions.map(\.name).sorted() == ["add", "add", "repeat"])
    }

    @Test("a backticked method and its overload get distinct case identifiers")
    func overloadGetsItsSuffix() throws {
        let candidate = try Self.counter()
        let result = ViewModelActionEnumEmitter.emit(typeName: candidate.typeName, actions: candidate.actions)
        let identifiers = result.lifted.map { $0.caseName.replacingOccurrences(of: "`", with: "") }
        #expect(Set(identifiers).count == identifiers.count, "case identifiers collide: \(identifiers)")
        #expect(Set(identifiers) == ["add", "addX", "repeat"])
        // The keyword is escaped by the emitter now, not by the source's own spelling.
        #expect(result.source.contains("case .`repeat`: model.`repeat`()"))
    }

    /// One call shape per fixture, so each of the walker's two edits is guarded on its own.
    @Test("a call to a backticked method still drives it as an action",
          arguments: ["self.`next`()", "`next`()"])
    func backtickedCallMatchesItsMethod(_ call: String) throws {
        let source = """
        import Observation

        @Observable
        final class Pager {
            var page = 0
            func `next`() { page += 1 }
            func skip() { \(call) }
        }
        """
        let candidate = try #require(ViewModelDiscoverer.discover(source: source, file: "Pager.swift").first)
        #expect(candidate.actions.map(\.name).sorted() == ["next", "skip"])
    }

    /// Every word the compiler rejected unescaped, measured over swift-syntax 603's `Keyword` set as an enum
    /// case, a case pattern, an implicit member and a method call. Nine were missing from the hand-written
    /// list `needsBackticks` replaced: `Any`, `Protocol`, `Type`, `fileprivate`, `internal`,
    /// `precedencegroup`, `private`, `public` and `static`.
    static let measuredNeedsBackticks = [
        "Any", "Protocol", "Self", "Type", "as", "associatedtype", "break", "case", "catch", "class",
        "continue", "default", "defer", "deinit", "do", "else", "enum", "extension", "fallthrough", "false",
        "fileprivate", "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "let",
        "nil", "operator", "precedencegroup", "private", "protocol", "public", "repeat", "rethrows", "return",
        "self", "static", "struct", "subscript", "super", "switch", "throw", "throws", "true", "try",
        "typealias", "var", "where", "while",
    ]

    @Test("every keyword the compiler rejects unescaped is escaped", arguments: measuredNeedsBackticks)
    func escapesMeasuredKeyword(_ word: String) {
        #expect(ViewModelActionEnumEmitter.needsBackticks(word))
    }

    @Test("contextual keywords and ordinary names stay bare",
          arguments: ["get", "set", "async", "await", "some", "any", "open", "final", "add", "reset"])
    func leavesContextualKeywordBare(_ word: String) {
        #expect(!ViewModelActionEnumEmitter.needsBackticks(word))
    }
}
