@testable import SwiftInferCore
import SwiftParser
import SwiftSyntax
import Testing

/// #671's body gate (`DedupeBodyReader`, SwiftInferProperties#711), run on the frozen scope's §4
/// controls (`docs/plans/dedupe-count-law-census-scope.md`) and on #711's two added forms.
///
/// The real subjects are quoted verbatim; a control whose name the shipped gate does not read
/// (`dedupedByIdentity`, `uniqued`) is renamed to a recognised name with its body unchanged, so the
/// body rule is what the test exercises.
@Suite("DedupeBodyReader — #671's body gate")
struct DedupeBodyReaderTests {

    private func reading(_ source: String) throws -> DedupeBodyReader.Reading? {
        let first = Parser.parse(source: source)
            .tokens(viewMode: .sourceAccurate)
            .lazy
            .compactMap { $0.parent?.as(FunctionDeclSyntax.self) }
            .first
        let function = try #require(first)
        return DedupeBodyReader.reading(of: function)
    }

    private static let set = DedupeBodyReader.Reading.admitted(DedupeBody(route: .set))
    private static let dictionary = DedupeBodyReader.Reading.admitted(DedupeBody(route: .dictionary))

    /// A correct Set-route body over `[Int]`, with `extra` spliced in at the top of the loop.
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

    // MARK: - Admitted

    @Test("SwiftUMLBridge `dedupe(relationships:)`, verbatim: Set route, keep-first")
    func swiftUMLBridgeDedupe() throws {
        let source = """
        static func dedupe(relationships: [ERRelationship]) -> [ERRelationship] {
            var seen: Set<String> = []
            var result: [ERRelationship] = []
            for relationship in relationships {
                let endpoints = [relationship.from, relationship.toEntity].sorted()
                let labels = [relationship.label, relationship.inverseLabel ?? ""].sorted()
                let key = "\\(endpoints[0])|\\(endpoints[1])|\\(labels[0])|\\(labels[1])"
                if !seen.contains(key) {
                    seen.insert(key)
                    result.append(relationship)
                }
            }
            return result
        }
        """
        #expect(try reading(source) == Self.set)
        #expect(DedupeBody(route: .set).keepsFirst)
    }

    @Test("`ConstructionUniverse.deduplicated`, verbatim: dictionary route, not keep-first")
    func constructionUniverseDeduplicated() throws {
        let source = """
        static func deduplicated(_ members: [Member]) -> [Member] {
            var byKey: [String: Member] = [:]
            for member in members {
                if let kept = byKey[member.key], kept.relativePath < member.relativePath { continue }
                byKey[member.key] = member
            }
            return Array(byKey.values)
        }
        """
        #expect(try reading(source) == Self.dictionary)
        #expect(!DedupeBody(route: .dictionary).keepsFirst)
    }

    @Test("`dedupedByStateAndAction`'s body, `insert(_:).inserted`: Set route")
    func insertedForm() throws {
        let source = """
        static func dedupe(_ candidates: [ReducerCandidate]) -> [ReducerCandidate] {
            var seen: Set<String> = []
            var result: [ReducerCandidate] = []
            for candidate in candidates {
                let key = (candidate.moduleName ?? "") + "|"
                    + candidate.stateQualifiedName + "|" + candidate.actionQualifiedName
                if seen.insert(key).inserted {
                    result.append(candidate)
                }
            }
            return result
        }
        """
        #expect(try reading(source) == Self.set)
    }

    @Test("the filter form, `EqualityBodyShape.deduplicated` verbatim")
    func filterForm() throws {
        let source = """
        private static func deduplicated(_ names: [String]) -> [String] {
            var seen: Set<String> = []
            return names.filter { seen.insert($0).inserted }
        }
        """
        #expect(try reading(source) == Self.set)
    }

    @Test("#711: `insert(_:).0`, as ArgumentParser's `uniquing()` spells it")
    func tupleFieldForm() throws {
        let source = """
        func dedupe(_ xs: [Int]) -> [Int] { var seen = Set<Int>(); return xs.filter { seen.insert($0).0 } }
        """
        #expect(try reading(source) == Self.set)
    }

    @Test("#711: `for … where !seen.contains(k)`, `deduplicateByPropertyName`'s body")
    func whereContainsForm() throws {
        let source = """
        private static func deduplicate(_ fields: [CardinalityWitness.Field]) -> [CardinalityWitness.Field] {
            var seen: Set<String> = []
            var result: [CardinalityWitness.Field] = []
            for field in fields where !seen.contains(field.propertyName) {
                seen.insert(field.propertyName)
                result.append(field)
            }
            return result
        }
        """
        #expect(try reading(source) == Self.set)
    }

    @Test("#711: `for … where seen.insert(k).inserted`")
    func whereInsertedForm() throws {
        let source = """
        func dedupe(_ xs: [Site]) -> [Site] {
            var seen = Set<String>()
            var result = [Site]()
            for site in xs where seen.insert(site.location).inserted { result.append(site) }
            return result
        }
        """
        #expect(try reading(source) == Self.set)
    }

    @Test("the guard form: `guard seen.insert(k).inserted else { continue }`")
    func guardForm() throws {
        let source = """
        func deduplicated(_ xs: [Int]) -> [Int] {
            var seen = Set<Int>()
            var result: [Int] = []
            for x in xs {
                guard seen.insert(x).inserted else { continue }
                result.append(x)
            }
            return result
        }
        """
        #expect(try reading(source) == Self.set)
    }

    // MARK: - Outside the gate: name or shape

    @Test("names and shapes the gate does not read answer nil, not a refusal")
    func outsideTheGate() throws {
        // A name the census's widened family holds but no template recognises today.
        #expect(try reading(Self.setLoop(name: "uniqued")) == nil)
        #expect(try reading(Self.setLoop(name: "dedupeRelationships")) == nil)
        // The key closure and the two-array form.
        #expect(try reading("func dedupe(_ xs: [Int], by key: (Int) -> Int) -> [Int] { xs }") == nil)
        #expect(try reading("func deduplicated(_ a: [Int], _ b: [Int]) -> [Int] { a }") == nil)
        #expect(try reading("func dedupe(by xs: [Int]) -> [Int] { xs }") == nil)
        // The receiver form, and effects.
        #expect(try reading("extension Array { func deduplicated() -> [Element] { self } }") == nil)
        #expect(try reading("func dedupe(_ xs: [Int]) throws -> [Int] { xs }") == nil)
        #expect(try reading("func dedupe(_ xs: inout [Int]) -> [Int] { xs }") == nil)
        #expect(try reading("func dedupe(_ xs: [Int]) -> [String] { [] }") == nil)
    }

    @Test("a generic dedupe is still read: admission is the body's question, emission the stub's")
    func genericIsRead() throws {
        let source = """
        func deduplicated<T: Hashable>(_ xs: [T]) -> [T] {
            var seen = Set<T>()
            return xs.filter { seen.insert($0).inserted }
        }
        """
        #expect(try reading(source) == Self.set)
    }
}
