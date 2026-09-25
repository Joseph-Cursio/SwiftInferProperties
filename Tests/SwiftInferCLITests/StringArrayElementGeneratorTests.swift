@testable import SwiftInferCLI
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The elements of a top-level `[String]` get the String carrier's own draw — edge-biased for a
/// structural law, hostile for totality — instead of the kit's plain alphanumeric elements, which
/// never produce the leading space `deindent(_:)` reads.
@Suite("[String] elements draw like a String carrier")
struct StringArrayElementGeneratorTests {

    @Test("a [String] carrier's elements are edge-biased, carrying the subject's literals")
    func arrayElementsAreEdgeBiased() {
        let generator = LiftedTestEmitter.defaultGenerator(for: "[String]", subjectLiterals: ["  "])
        #expect(generator.hasPrefix("(Gen.frequency("))
        #expect(generator.hasSuffix(").array(of: 0...8)"))
        #expect(generator.contains("\"  \""))
    }

    @Test("a totality argument of [String] gets hostile elements")
    func totalityElementsAreHostile() {
        let hostile = LiftedTestEmitter.hostileGenerator(for: "[String]")
        let single = LiftedTestEmitter.hostileGenerator(for: "String")
        #expect(hostile == "(\(single)).array(of: 0...8)")
    }

    @Test("a dictionary, an array of another type, and nested arrays keep the kit's form",
          arguments: ["[String: Int]", "[Int]", "[[String]]"])
    func otherCollectionsAreUnchanged(typeName: String) {
        #expect(LiftedTestEmitter.arrayElement(of: typeName) == (typeName == "[Int]" ? "Int" : nil))
        #expect(!LiftedTestEmitter.defaultGenerator(for: typeName).hasPrefix("(Gen.frequency("))
    }
}
