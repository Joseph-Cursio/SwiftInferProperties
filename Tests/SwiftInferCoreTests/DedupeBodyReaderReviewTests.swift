@testable import SwiftInferCore
import SwiftParser
import SwiftSyntax
import Testing

/// The counterexamples #734's adversarial review reproduced against the first gate. Each one was
/// admitted, and C1 or C2 was then false of the function as written: the tool proposed a false law
/// against correct code. Every one must now be refused, and the forms beside them stay admitted.
@Suite("DedupeBodyReader — the review's counterexamples")
struct DedupeBodyReaderReviewTests {

    private func reading(_ source: String) throws -> DedupeBodyReader.Reading? {
        let first = Parser.parse(source: source)
            .tokens(viewMode: .sourceAccurate)
            .lazy
            .compactMap { $0.parent?.as(FunctionDeclSyntax.self) }
            .first
        let function = try #require(first)
        return DedupeBodyReader.reading(of: function)
    }

    private static func dictionary(skip: String) -> String {
        """
        static func dedupe(_ xs: [Int]) -> [Int] {
            var seen = [Int: Int]()
            for x in xs {
                \(skip)
                seen[x] = x
            }
            return Array(seen.values)
        }
        """
    }

    private static func setLoop(_ loopBody: String) -> String {
        """
        static func dedupe(_ xs: [Int]) -> [Int] {
            var seen = Set<Int>()
            var result: [Int] = []
            for x in xs {
                \(loopBody)
            }
            return result
        }
        """
    }

    // MARK: - A dictionary skip must test that the written key is present

    @Test("a skip that also filters (`||`, a comma, the wrong polarity) is refused: C1 is false of it",
          arguments: [
              "if seen[x] != nil || x < 0 { continue }",
              "if x < 0 || seen[x] != nil { continue }",
              "if x % 2 == 0, seen[x] == nil { continue }",
              "if seen[x] == nil { continue }",
              "if x < 0, let kept = seen[x] { continue }",
          ])
    func dictionaryFilterIsRefused(skip: String) throws {
        #expect(try reading(Self.dictionary(skip: skip)) == .refused(DedupeBodyReader.Refusal.otherSkip))
    }

    @Test("a presence test, alone or narrowed by a conjunct, is admitted",
          arguments: [
              "if seen[x] != nil { continue }",
              "if let kept = seen[x] { continue }",
              "if let kept = seen[x], kept < x { continue }",
          ])
    func presenceSkipIsAdmitted(skip: String) throws {
        #expect(try reading(Self.dictionary(skip: skip)) == .admitted(DedupeBody(route: .dictionary)))
    }

    @Test("a conjunct that names the dictionary is refused")
    func conjunctNamingTheDictionary() throws {
        let source = Self.dictionary(skip: "if let kept = seen[x], seen.count > 3 { continue }")
        #expect(try reading(source) == .refused(DedupeBodyReader.Refusal.otherSkip))
    }

    @Test("a `let` that mutates the dictionary is refused")
    func dictionaryLetMutates() throws {
        let source = Self.dictionary(skip: "let _ = seen.removeValue(forKey: x - 1)")
        #expect(try reading(source) == .refused(DedupeBodyReader.Refusal.unread))
    }

    // MARK: - A `let` is read, not waved through

    @Test("a `let` that touches the set is refused: it pre-inserts or removes keys",
          arguments: [
              "let _ = x < 0 ? seen.insert(x) : (false, x); if seen.insert(x).inserted { result.append(x) }",
              "let _ = seen.insert(x); if seen.insert(x).inserted { result.append(x) }",
              "let keep: Bool = { if x < 0 { _ = seen.insert(x) }; return true }(); "
                  + "if seen.insert(x).inserted { result.append(x) }",
              "let _ = x == 0 ? seen.remove(0) : nil; if seen.insert(x).inserted { result.append(x) }",
          ])
    func letTouchingTheSet(loopBody: String) throws {
        #expect(try reading(Self.setLoop(loopBody)) == .refused(DedupeBodyReader.Refusal.unread))
    }

    @Test("a `let` that appends is refused: an element reaches the result past the insert")
    func letAppends() throws {
        let source = Self.setLoop("let _ = result.append(x); if seen.insert(x).inserted { result.append(x) }")
        #expect(try reading(source) == .refused(DedupeBodyReader.Refusal.appendNotBehindInsert))
    }

    @Test("a `let` computing the key is still admitted")
    func inertLet() throws {
        let source = Self.setLoop("let key = x / 2; if seen.insert(key).inserted { result.append(x) }")
        #expect(try reading(source) == .admitted(DedupeBody(route: .set)))
    }

    // MARK: - One append per element, keyed by the element

    @Test("two appends per element are refused: C1 would see two",
          arguments: [
              "if seen.insert(x).inserted { result.append(x); result.append(x) }",
              "if seen.insert(x).inserted { result.append(x) }; if seen.insert(-x).inserted { result.append(x) }",
              "guard seen.insert(x).inserted else { continue }; result.append(x); result.append(x)",
          ])
    func twoAppends(loopBody: String) throws {
        #expect(try reading(Self.setLoop(loopBody)) == .refused(DedupeBodyReader.Refusal.unread))
    }

    @Test("a key computed from the result or from the set is refused",
          arguments: [
              "if seen.insert(result.count).inserted { result.append(x) }",
              "if seen.insert(seen.count).inserted { result.append(x) }",
              "if !seen.contains(x + result.count) { seen.insert(x + result.count); result.append(x) }",
          ])
    func keyFromALocal(loopBody: String) throws {
        #expect(try reading(Self.setLoop(loopBody)) == .refused(DedupeBodyReader.Refusal.unread))
    }
}
