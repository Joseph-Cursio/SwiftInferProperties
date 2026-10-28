@testable import SwiftPlantUMLFramework
import XCTest

final class PlantUMLContextUniqNameTests: XCTestCase {
    /// a decorated name ("A0") is issued first, then a type that is really called "A0"
    func testUniqNameDoesNotReissueDecoratedNameToTypeWithThatName() {
        let context = PlantUMLContext()

        let first = context.uniqName(item: SyntaxStructure(kind: .struct, name: "A"), relationship: "inherits")
        let second = context.uniqName(item: SyntaxStructure(kind: .struct, name: "A"), relationship: "inherits")
        let third = context.uniqName(item: SyntaxStructure(kind: .struct, name: "A0"), relationship: "inherits")

        XCTAssertEqual(first, "A")
        XCTAssertEqual(second, "A0")
        XCTAssertNotEqual(third, second)
        XCTAssertEqual(Set([first, second, third]).count, 3)
    }

    /// a type that is really called "A0" is issued first, then a decoration of "A" would spell "A0"
    func testUniqNameDoesNotDecorateIntoNameAlreadyIssued() {
        let context = PlantUMLContext()

        let first = context.uniqName(item: SyntaxStructure(kind: .struct, name: "A0"), relationship: "inherits")
        let second = context.uniqName(item: SyntaxStructure(kind: .struct, name: "A"), relationship: "inherits")
        let third = context.uniqName(item: SyntaxStructure(kind: .struct, name: "A"), relationship: "inherits")

        XCTAssertEqual(first, "A0")
        XCTAssertEqual(second, "A")
        XCTAssertNotEqual(third, first)
        XCTAssertEqual(Set([first, second, third]).count, 3)
    }

    func testExtensionDoesNotShareAliasWithAnotherTypeE2E() {
        let code = """
        struct Vector {}
        struct Vector2 {}
        struct Vector3 {}

        extension Vector2 {}
        extension Vector3 {}
        extension Vector {}
        """
        guard let items = SyntaxStructure.create(from: code)?.substructure else { return XCTFail("cannot read test data") }
        let script = PlantUMLScript(items: items)

        let aliases = declaredAliases(in: script.text)
        XCTAssertEqual(aliases.count, 6)
        XCTAssertEqual(aliases.count, Set(aliases).count, "an alias is declared twice: \(aliases)")
        XCTAssertFalse(script.text.contains("Vector <.. Vector2 : ext"))
        XCTAssertFalse(script.text.contains("Vector <.. Vector3 : ext"))
    }

    func testDecoratedAliasIsNotSharedWithLaterTypeE2E() {
        let code = """
        struct Item {}
        struct Item {}
        struct Item0 {}
        """
        guard let items = SyntaxStructure.create(from: code)?.substructure else { return XCTFail("cannot read test data") }
        let script = PlantUMLScript(items: items)

        let aliases = declaredAliases(in: script.text)
        XCTAssertEqual(aliases.count, 3)
        XCTAssertEqual(aliases.count, Set(aliases).count, "an alias is declared twice: \(aliases)")
    }

    /// no top-level type "Item0" is in the diagram, so the extension must not be linked to the alias "Item0" (the second Item)
    func testExtensionOfAbsentTypeIsNotLinkedToDecoratedAliasE2E() {
        let code = """
        struct Item {}
        struct Item {}
        struct Outer { struct Item0 {} }
        extension Item0 {}
        """
        guard let items = SyntaxStructure.create(from: code)?.substructure else { return XCTFail("cannot read test data") }
        let script = PlantUMLScript(items: items)

        let aliases = declaredAliases(in: script.text)
        XCTAssertEqual(aliases.count, 5)
        XCTAssertEqual(aliases.count, Set(aliases).count, "an alias is declared twice: \(aliases)")
        let extLines = script.text.components(separatedBy: "\n").filter { $0.hasPrefix("Item0 <.. ") }
        XCTAssertEqual(extLines, [], "an ext line points at the alias of the second Item")
    }

    /// aliases of all element declarations, i.e. `Alias` in `class "Name" as Alias << ... >> {`
    func declaredAliases(in text: String) -> [String] {
        text.components(separatedBy: "\n").compactMap { line in
            guard line.hasPrefix("class \""), let asRange = line.range(of: "\" as ") else { return nil }
            let rest = line[asRange.upperBound...]
            return String(rest.prefix(while: { $0 != " " && $0 != "<" }))
        }
    }
}
