import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// **`UniquifierTemplate` through `discover`** (#692): the gate's criterion 1, the setup and recycling
/// declines the census measured, the memoizing and `inout` forms, and the Possible tier.
@Suite("Uniquifier template — #669's law, gated and declined as the census measured")
struct UniquifierTemplateTests {

    private func suggestions(_ source: String) -> [Suggestion] {
        let corpus = FunctionScanner.scanCorpus(source: source, file: "U.swift")
        return TemplateRegistry.discover(
            in: corpus.summaries,
            typeDecls: corpus.typeDecls,
            templateFilter: [UniquifierTemplate.name]
        )
    }

    private func reason(_ name: String, in source: String) throws -> String? {
        let summaries = FunctionScanner.scan(source: source, file: "U.swift")
        let summary = try #require(summaries.first { $0.name == name })
        return UniquifierTemplate.declineReason(for: summary, siblings: summaries)
    }

    private static let witness = """
    final class DiagramContext {
        var uniqElementNames: [String] = []
        var index = 0
        func uniqName(item: Item, relationship: String) -> String {
            guard let name = item.fullName else { return "" }
            var newName = name
            if uniqElementNames.contains(name) {
                newName += "\\(index)"
                index += 1
            } else {
                uniqElementNames.append(name)
            }
            return newName
        }
    }
    """

    @Test("#669's witness is proposed at Possible, with its sentinel and a placeholder for the argument")
    func witnessIsProposed() throws {
        let found = try #require(suggestions(Self.witness).first)
        #expect(found.templateName == "uniquifier")
        #expect(found.score.tier == .possible)
        #expect(found.score.total == 35)
        let match = try #require(found.match?.uniquifierMatch)
        #expect(match.form == .instance)
        #expect(match.nameParameter == nil)
        #expect(match.parameterTypes == ["Item", "String"])
        let caveats = found.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("THE LEADING GUARD REJECTS GETS \"\""))
        #expect(caveats.contains("leaves a placeholder"))
    }

    @Test("a sibling that fills the tested state first declines the subject as a setup call")
    func setupCallDeclines() throws {
        let source = """
        final class DiagramContext {
            var uniqElementNames: [String] = []
            var takenIdentifiers: Set<String> = []
            var index = 0
            func reserveIdentifiers(drawing items: [Item]) {
                for item in items { takenIdentifiers.insert(item.name) }
            }
            func uniqName(item: Item, relationship: String) -> String {
                guard let name = item.fullName else { return "" }
                var newName = name
                if uniqElementNames.contains(name) {
                    repeat {
                        newName = name + "\\(index)"
                        index += 1
                    } while takenIdentifiers.contains(newName)
                } else {
                    uniqElementNames.append(name)
                }
                takenIdentifiers.insert(newName)
                return newName
            }
        }
        """
        #expect(suggestions(source).isEmpty)
        let why = try #require(try reason("uniqName", in: source))
        #expect(why.hasPrefix("SETUP: `reserveIdentifiers` writes `takenIdentifiers`"))
    }

    @Test("two issuers over one state are not each other's setup call")
    func coIssuersAreBothProposed() {
        let source = """
        final class Graph {
            var used: Set<String> = []
            func registerCluster(_ base: String) -> String {
                var name = base
                while used.contains(name) { name = name + "_" }
                used.insert(name)
                return name
            }
            func openSubgraph(_ base: String) -> String {
                var name = base
                while used.contains(name) { name = name + "_" }
                used.insert(name)
                return name
            }
        }
        """
        #expect(Set(suggestions(source).compactMap { $0.evidence.first?.displayName }).count == 2)
    }

    @Test("a sibling that releases names declines the subject as a recycling pool")
    func recyclingDeclines() throws {
        let source = """
        final class Pool {
            var used: Set<String> = []
            var next = 0
            func issue(_ base: String) -> String {
                var name = base
                while used.contains(name) {
                    name = "\\(base)\\(next)"
                    next += 1
                }
                used.insert(name)
                return name
            }
            func release(_ name: String) {
                used.remove(name)
            }
        }
        """
        #expect(suggestions(source).isEmpty)
        let why = try #require(try reason("issue", in: source))
        #expect(why.hasPrefix("RECYCLING: `release` removes from `used`"))
    }

    @Test("a mutating memoizing method on a struct takes the memoizing law and a runnable name")
    func memoizingMutatingForm() throws {
        let source = """
        struct DiagramIdentifiers {
            var byKey: [String: String] = [:]
            var taken: Set<String> = []
            mutating func id(forKey key: String) -> String {
                if let existing = byKey[key] { return existing }
                var candidate = key
                var n = 2
                while taken.contains(candidate) {
                    candidate = "\\(key)_\\(n)"
                    n += 1
                }
                taken.insert(candidate)
                byKey[key] = candidate
                return candidate
            }
        }
        """
        let found = try #require(suggestions(source).first)
        let match = try #require(found.match?.uniquifierMatch)
        #expect(match.form == .mutating)
        #expect(match.nameParameter == 0)
        #expect(match.shape.isMemoizing)
        #expect(found.explainability.whyMightBeWrong.first?.hasPrefix("MEMOIZING") == true)
        #expect(found.score.total == 25)
    }

    @Test("a free function over an inout collection carries the collection's type")
    func inoutForm() throws {
        let source = """
        func uniqueCaseName(for base: String, taken: inout Set<String>) -> String {
            var name = base
            var suffix = 2
            while taken.contains(name) {
                name = "\\(base)\\(suffix)"
                suffix += 1
            }
            taken.insert(name)
            return name
        }
        """
        let match = try #require(suggestions(source).first?.match?.uniquifierMatch)
        #expect(match.form == .inoutParameter(index: 1, collectionType: "Set<String>"))
        #expect(match.nameParameter == 0)
    }

    @Test("an actor's method, an async method and a struct's non-mutating method are not proposed")
    func outOfReachFormsAreNotProposed() {
        let actor = Self.witness.replacingOccurrences(of: "final class", with: "actor")
        let async = Self.witness.replacingOccurrences(
            of: "relationship: String) -> String",
            with: "relationship: String) async -> String"
        )
        let value = Self.witness.replacingOccurrences(of: "final class", with: "struct")
        #expect(suggestions(actor).isEmpty)
        #expect(suggestions(async).isEmpty)
        #expect(suggestions(value).isEmpty)
    }
}
