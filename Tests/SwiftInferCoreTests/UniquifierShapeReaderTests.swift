import SwiftInferCore
import Testing

/// **`UniquifierShapeReader` against the census's own shapes** (#692). Each source below is a body the
/// census judged (`docs/measurements/uniquifier-law-census.md`), trimmed to what the cues read, or one
/// of the shapes #669 says the gate must reject.
@Suite("Uniquifier shape — #669's criteria 2 and 3, read off the body")
struct UniquifierShapeReaderTests {

    private func summary(_ name: String, in source: String) throws -> FunctionSummary {
        try #require(FunctionScanner.scan(source: source, file: "U.swift").first { $0.name == name })
    }

    private func shape(_ name: String, in source: String) throws -> UniquifierShape? {
        try summary(name, in: source).bodySignals.uniquifierShape
    }

    /// SwiftUMLStudio's `uniqName` at `e36da59`, #669's witness: the suffix is never re-checked.
    @Test("the witness's defective uniqName is gated, with its sentinel")
    func defectiveUniqNameIsGated() throws {
        let source = """
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
        let found = try #require(try shape("uniqName", in: source))
        #expect(found.testedBases == ["uniqElementNames"])
        #expect(found.decoration == .counter(prefix: ""))
        #expect(found.sentinel == "\"\"")
        #expect(!found.isMemoizing)
        #expect(found.testLine == 7)
        #expect(found.writeLine == 11)
    }

    /// The fixed `uniqName`: a `repeat` re-checks every candidate against `takenIdentifiers`.
    @Test("the fixed uniqName is gated through its repeat loop")
    func fixedUniqNameIsGated() throws {
        let source = """
        final class DiagramContext {
            var uniqElementNames: [String] = []
            var takenIdentifiers: Set<String> = []
            var index = 0
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
        let found = try #require(try shape("uniqName", in: source))
        #expect(found.testedBases == ["takenIdentifiers", "uniqElementNames"])
    }

    /// swift-syntax's `makeUniqueName`: a per-name counter read from the tested table.
    @Test("makeUniqueName is gated by its per-key counter")
    func makeUniqueNameIsGated() throws {
        let source = """
        public class BasicMacroExpansionContext {
            private var uniqueNames: [String: Int] = [:]
            public func makeUniqueName(_ providedName: String) -> TokenSyntax {
                let uniqueIndex = uniqueNames[providedName, default: 0]
                uniqueNames[providedName] = uniqueIndex + 1
                var resultString = "$s"
                resultString += "\\(providedName.count)\\(providedName)"
                resultString += "fMu"
                if uniqueIndex > 0 { resultString += "\\(uniqueIndex - 1)" }
                resultString += "_"
                return TokenSyntax(.identifier(resultString), presence: .present)
            }
        }
        """
        let found = try #require(try shape("makeUniqueName", in: source))
        #expect(found.testedBases == ["uniqueNames"])
    }

    /// A memoizing uniquifier: an early return of the id stored for a seen key.
    @Test("an early return of a stored id reads as memoizing, with an underscore suffix")
    func memoizingFormIsRead() throws {
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
        let found = try #require(try shape("id", in: source))
        #expect(found.isMemoizing)
        #expect(found.decoration == .counter(prefix: "_"))
        #expect(found.sentinel == nil)
    }

    /// RETEST: a loop that appends text until the candidate is free, with no counter at all.
    @Test("a re-test loop that appends text is gated, and spells what it appends")
    func retestLoopIsGated() throws {
        let source = """
        final class Namer {
            var used: Set<String> = []
            func fresh(_ base: String) -> String {
                var name = base
                while used.contains(name) {
                    name = name + "_"
                }
                used.insert(name)
                return name
            }
        }
        """
        let found = try #require(try shape("fresh", in: source))
        #expect(found.decoration == .appended("_"))
    }

    /// A function with an `inout` collection keeps its state in the caller's collection.
    @Test("a free function over an inout collection is read")
    func inoutFormIsRead() throws {
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
        let found = try #require(try shape("uniqueCaseName", in: source))
        #expect(found.testedBases == ["taken"])
    }

    /// #669's counterexample `uniqueId`: it tests and decorates, but its caller does the registering.
    @Test("a lookup whose caller registers the result is not gated (#669's C3)")
    func uniqueIdIsNotGated() throws {
        let source = """
        final class LayoutGraphBuilder {
            func uniqueId(for name: String, existing: [String: String]) -> String {
                if existing[name] == nil { return name }
                var counter = 1
                var candidate = "\\(name)_\\(counter)"
                while existing.values.contains(candidate) {
                    counter += 1
                    candidate = "\\(name)_\\(counter)"
                }
                return candidate
            }
        }
        """
        #expect(try shape("uniqueId", in: source) == nil)
    }

    @Test("a counter-only generator has no test, so it is not gated")
    func counterOnlyIsNotGated() throws {
        let source = """
        final class Labels {
            var counter = 0
            func nextName(_ prefix: String) -> String {
                counter += 1
                return "\\(prefix)\\(counter)"
            }
        }
        """
        #expect(try shape("nextName", in: source) == nil)
    }

    @Test("a dedup helper over a local set is not gated")
    func dedupHelperIsNotGated() throws {
        let source = """
        extension Array where Element: Hashable {
            func uniqued() -> [Element] {
                var seen: Set<Element> = []
                return filter { seen.insert($0).inserted }
            }
        }
        """
        #expect(try shape("uniqued", in: source) == nil)
    }

    @Test("a static function keeps no state across calls, so it is not read")
    func staticIsNotRead() throws {
        let source = """
        final class Namer {
            static var used: Set<String> = []
            static func fresh(_ base: String) -> String {
                var name = base
                while used.contains(name) { name = name + "_" }
                used.insert(name)
                return name
            }
        }
        """
        #expect(try shape("fresh", in: source) == nil)
    }

    /// The sibling facts the template reads: a setup call writes the tested state, a reset removes it.
    @Test("state writes record what a method writes and what it removes")
    func stateWritesAreRecorded() throws {
        let source = """
        final class DiagramContext {
            var takenIdentifiers: Set<String> = []
            var names: [String] = []
            func reserveIdentifiers(drawing items: [Item]) {
                for item in items {
                    takenIdentifiers.insert(item.name)
                }
                takenIdentifiers.formUnion(items.map(\\.alias))
            }
            func release(_ name: String) {
                names.removeAll { $0 == name }
            }
        }
        """
        let reserve = try summary("reserveIdentifiers", in: source).bodySignals.stateWrites
        #expect(reserve == StateWrites(written: ["takenIdentifiers"], removed: []))
        let release = try summary("release", in: source).bodySignals.stateWrites
        #expect(release == StateWrites(written: [], removed: ["names"]))
    }
}
