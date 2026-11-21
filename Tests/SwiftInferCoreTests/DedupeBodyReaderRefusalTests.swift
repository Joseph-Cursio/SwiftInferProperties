@testable import SwiftInferCore
import SwiftParser
import SwiftSyntax
import Testing

/// #671's body gate refusing what the count laws would be false of, or that it cannot read: the
/// frozen scope's §4 refusal controls (`docs/plans/dedupe-count-law-census-scope.md`), each with the
/// reason the census spelled. `DedupeBodyReaderTests` holds the admitted forms.
@Suite("DedupeBodyReader — refusals")
struct DedupeBodyReaderRefusalTests {

    private func reading(_ source: String) throws -> DedupeBodyReader.Reading? {
        let first = Parser.parse(source: source)
            .tokens(viewMode: .sourceAccurate)
            .lazy
            .compactMap { $0.parent?.as(FunctionDeclSyntax.self) }
            .first
        let function = try #require(first)
        return DedupeBodyReader.reading(of: function)
    }

    /// A correct Set-route body over `[Int]` named `name`, with `loopPrefix` spliced in at the top of
    /// the loop and `afterLoop` between the loop and the return.
    private static func setLoop(name: String = "dedupe", loopPrefix: String = "", afterLoop: String = "") -> String {
        """
        func \(name)(_ xs: [Int]) -> [Int] {
            var seen = Set<Int>()
            var result: [Int] = []
            for x in xs {
                \(loopPrefix)
                if seen.insert(x).inserted { result.append(x) }
            }
            \(afterLoop)
            return result
        }
        """
    }

    @Test("`dedupedByIdentity`'s body: refused, early return")
    func earlyReturn() throws {
        let source = """
        static func deduplicated(_ suggestions: [Suggestion]) -> [Suggestion] {
            var countsByIdentity: [String: Int] = [:]
            for suggestion in suggestions {
                countsByIdentity[suggestion.identity.normalized, default: 0] += 1
            }
            guard countsByIdentity.contains(where: { $0.value > 1 }) else { return suggestions }
            var seen: Set<String> = []
            var result: [Suggestion] = []
            for suggestion in suggestions {
                guard seen.insert(suggestion.identity.normalized).inserted else { continue }
                result.append(suggestion)
            }
            return result
        }
        """
        #expect(try reading(source) == .refused(DedupeBodyReader.Refusal.earlyReturn))
    }

    @Test("a dedupe that also filters: refused, other skip")
    func alsoFilters() throws {
        let source = Self.setLoop(loopPrefix: "guard x > 0 else { continue }")
        #expect(try reading(source) == .refused(DedupeBodyReader.Refusal.otherSkip))
    }

    @Test("a `where` that filters: refused, other skip")
    func whereFilters() throws {
        let source = """
        func dedupe(_ xs: [Int]) -> [Int] {
            var seen = Set<Int>()
            var result: [Int] = []
            for x in xs where x > 0 { if seen.insert(x).inserted { result.append(x) } }
            return result
        }
        """
        #expect(try reading(source) == .refused(DedupeBodyReader.Refusal.otherSkip))
    }

    @Test("a pass-through of un-keyable elements: refused, append not behind an insert")
    func passThrough() throws {
        let source = """
        func dedupe(_ xs: [Item]) -> [Item] {
            var seen = Set<Int>()
            var result: [Item] = []
            for x in xs {
                guard let id = x.id else { result.append(x); continue }
                if seen.insert(id).inserted { result.append(x) }
            }
            return result
        }
        """
        #expect(try reading(source) == .refused(DedupeBodyReader.Refusal.appendNotBehindInsert))
    }

    @Test("an extra append after the loop: refused, append not behind an insert")
    func extraAppend() throws {
        let source = Self.setLoop(afterLoop: "result.append(0)")
        #expect(try reading(source) == .refused(DedupeBodyReader.Refusal.appendNotBehindInsert))
    }

    @Test("an unguarded append in the loop: refused, append not behind an insert")
    func unguardedAppend() throws {
        let source = Self.setLoop(loopPrefix: "result.append(x)")
        #expect(try reading(source) == .refused(DedupeBodyReader.Refusal.appendNotBehindInsert))
    }

    @Test("no Set or dictionary local: refused")
    func noLocal() throws {
        let source = "func dedupe(_ xs: [Int]) -> [Int] { return Array(Set(xs)) }"
        #expect(try reading(source) == .refused(DedupeBodyReader.Refusal.noLocal))
    }

    @Test("contains one key, inserts another: refused, unread")
    func mismatchedKeys() throws {
        let source = """
        func dedupe(_ xs: [Item]) -> [Item] {
            var seen = Set<Int>()
            var result: [Item] = []
            for x in xs {
                if !seen.contains(x.id) {
                    seen.insert(x.other)
                    result.append(x)
                }
            }
            return result
        }
        """
        #expect(try reading(source) == .refused(DedupeBodyReader.Refusal.unread))
    }

    @Test("a dictionary skip that reads no key: refused, other skip")
    func dictionarySkipWithoutRead() throws {
        let source = """
        static func deduplicated(_ members: [Member]) -> [Member] {
            var byKey: [String: Member] = [:]
            for member in members {
                if member.isHidden { continue }
                byKey[member.key] = member
            }
            return Array(byKey.values)
        }
        """
        #expect(try reading(source) == .refused(DedupeBodyReader.Refusal.otherSkip))
    }
}
