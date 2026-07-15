import Foundation
@testable import SwiftInferCLI
import Testing

/// V1.145 — the standard-library known-properties catalog + renderer.
@Suite("KnownProperties — V1.145 stdlib catalog")
struct KnownPropertiesTests {

    // MARK: - Catalog structure

    @Test("V1.145 — every law carries a checkBody; every caveat has no checkBody but a note")
    func catalogStructure() {
        for property in StandardLibraryProperties.all {
            switch property.kind {
            case .law:
                #expect(property.checkBody != nil, "law missing checkBody: \(property.displayName)")

            case .caveat:
                #expect(property.checkBody == nil, "caveat should not be verifiable: \(property.displayName)")
                #expect(property.note != nil, "caveat should carry a note: \(property.displayName)")
            }
        }
        #expect(!StandardLibraryProperties.laws.isEmpty)
        #expect(!StandardLibraryProperties.caveats.isEmpty)
    }

    @Test("V1.145 — laws are tagged with the kit protocol they witness")
    func witnessTags() {
        func witness(_ type: String, _ statement: String) -> String?? {
            StandardLibraryProperties.laws.first {
                $0.type == type && $0.statement == statement
            }?.witnesses
        }
        // Int under + is a CommutativeMonoid; max is a Semilattice.
        #expect(witness("Int", "a + b == b + a") == "CommutativeMonoid")
        #expect(witness("Int", "max(a, b) == max(b, a)") == "Semilattice")
        // Set union / Bool && are Semilattices; String + is a (non-commutative) Monoid.
        #expect(witness("Set", "a.union(b) == b.union(a)") == "Semilattice")
        #expect(witness("String", "(a + b) + c == a + (b + c)") == "Monoid")
        // Double witnesses NO protocol (commutative + identity, but not associative).
        for law in StandardLibraryProperties.laws where law.type == "Double" {
            #expect(law.witnesses == nil, "Double is not a Monoid (not associative): \(law.statement)")
        }
        // Unary idempotence / involution are not algebraic protocols → no tag.
        #expect(witness("Int", "abs(abs(a)) == abs(a)") == .some(nil))
        #expect(witness("Array", "a.reversed().reversed() == a") == .some(nil))
    }

    @Test("V1.145 — the known counter-signals are present as caveats")
    func caveatsCoverKnownTraps() {
        let caveatTypes = Set(StandardLibraryProperties.caveats.map(\.type))
        // Double non-associativity + String/Array non-commutativity are the
        // engine's canonical counter-signals — they must be documented, not
        // asserted true.
        #expect(caveatTypes.contains("Double"))
        #expect(caveatTypes.contains("String"))
        #expect(caveatTypes.contains("Array"))
        // Dictionary `merging` non-commutativity is the same class of trap.
        #expect(caveatTypes.contains("Dictionary"))
    }

    @Test("role distinguishes discover-anchors from documentation, derived from template")
    func roleDerivedFromTemplate() {
        // The invariant the field exists to hold: an entry anchors iff it has a
        // template `discover` can match — never drifting from that fact.
        for property in StandardLibraryProperties.all {
            let expected: KnownPropertyRole = property.template != nil ? .anchor : .reference
            #expect(property.role == expected, "role/template out of sync: \(property.displayName)")
        }

        func role(_ type: String, _ statement: String) -> KnownPropertyRole? {
            StandardLibraryProperties.all.first { $0.type == type && $0.statement == statement }?.role
        }
        // Anchors: a proven-analog law and a trap caveat both feed StdlibAnchor.
        #expect(role("Set", "a.union(b) == b.union(a)") == .anchor)
        #expect(role("Set", "subtracting is NOT commutative") == .anchor)   // a caveat, but enforced
        // Reference: true + self-verified, but no template names its shape.
        #expect(role("Optional", "o.map { $0 } == o") == .reference)
        #expect(role("Int", "abs(abs(a)) == abs(a)") == .reference)
    }

    @Test("common data types — Optional / Dictionary carry verifiable functor laws")
    func commonDataTypesCovered() {
        let lawTypes = Set(StandardLibraryProperties.laws.map(\.type))
        // The two most-common Swift containers after Array/Set are now covered.
        #expect(lawTypes.contains("Optional"))
        #expect(lawTypes.contains("Dictionary"))

        func statements(_ type: String) -> Set<String> {
            Set(StandardLibraryProperties.laws.filter { $0.type == type }.map(\.statement))
        }
        #expect(statements("Optional").contains("o.map { $0 } == o"))
        #expect(statements("Dictionary").contains("d.mapValues { $0 } == d"))
        // Every new law is executable — it must carry a checkBody, or `--verify`
        // silently skips it (a law you cannot run is not a property test).
        for law in StandardLibraryProperties.laws where law.type == "Optional" || law.type == "Dictionary" {
            #expect(law.checkBody != nil, "unrunnable law: \(law.displayName)")
        }
    }

    // MARK: - Listing

    @Test("V1.145 — renderList groups by type and includes a caveats section")
    func renderListGroups() {
        let out = KnownPropertiesRenderer.renderList(StandardLibraryProperties.all)
        #expect(out.contains("Int"))
        #expect(out.contains("Set"))
        #expect(out.contains("a.union(b) == b.union(a)"))
        #expect(out.contains("Caveats — plausible but FALSE"))
        #expect(out.contains("+ is NOT associative"))
    }

    @Test("V1.145 — renderList with verify results marks ✓/✗ and shows a tally")
    func renderListVerified() {
        let laws = StandardLibraryProperties.laws
        var results: [String: Bool] = [:]
        for law in laws { results[law.displayName] = true }
        // Flip one to failing to exercise the ✗ path.
        results[laws[0].displayName] = false
        let out = KnownPropertiesRenderer.renderList(StandardLibraryProperties.all, verifyResults: results)
        #expect(out.contains("✓ "))
        #expect(out.contains("✗ "))
        #expect(out.contains("Verified \(laws.count - 1)/\(laws.count) laws held"))
    }

    // MARK: - Verify program generation + parsing

    @Test("V1.145 — renderVerifyProgram emits the RNG preamble + one check per law")
    func verifyProgramShape() {
        let program = KnownPropertiesRenderer.renderVerifyProgram(StandardLibraryProperties.laws)
        #expect(program.contains("struct SeededRNG"))
        #expect(program.contains("func randInt()"))
        #expect(program.contains("func check("))
        // One check(...) call per law.
        let checkCount = program.components(separatedBy: "check(\"").count - 1
        #expect(checkCount == StandardLibraryProperties.laws.count)
        // A representative law body is inlined verbatim.
        #expect(program.contains("a.union(b) == b.union(a)"))
    }

    @Test("V1.145 — parseVerifyOutput reads PASS/FAIL lines")
    func parseOutput() {
        let output = "PASS\tInt: a + b == b + a\nFAIL\tSet: a.union(b) == b.union(a)\nnoise line\n"
        let results = KnownPropertiesRenderer.parseVerifyOutput(output)
        #expect(results["Int: a + b == b + a"] == true)
        #expect(results["Set: a.union(b) == b.union(a)"] == false)
        #expect(results.count == 2)
    }

    @Test("V1.145 — escaped names survive statements containing quotes (String identity)")
    func escapedQuotesInProgram() {
        // The `a + "" == a` law's name contains quotes; the generated program
        // must escape them so it compiles.
        let program = KnownPropertiesRenderer.renderVerifyProgram(StandardLibraryProperties.laws)
        #expect(program.contains(#"check("String: a + \"\" == a")"#))
    }
}
