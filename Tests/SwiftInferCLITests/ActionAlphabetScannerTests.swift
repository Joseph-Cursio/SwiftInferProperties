import Foundation
@testable import SwiftInferCLI
import Testing

// TestStore Trace Mining (Slice 3a) — ActionAlphabetScanner resolves an Action
// enum's cases + parameter labels/types for any carrier by scanning sources.

@Suite("ActionAlphabetScanner — Action enum resolution")
struct ActionAlphabetScannerTests {

    private func withSource(_ contents: String, _ body: (URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActionAlphabetScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(contents.utf8).write(to: dir.appendingPathComponent("Src.swift"))
        try body(dir)
    }

    @Test("Top-level enum by bare name → cases with labels and types")
    func topLevelBareName() throws {
        try withSource(
            """
            enum AppAction {
                case dismiss
                case select(Int)
                case setColor(color: String)
            }
            """
        ) { dir in
            let specs = ActionAlphabetScanner.scan(directory: dir, actionTypeName: "AppAction")
            #expect(specs.count == 3)
            #expect(specs[0] == ActionCaseSpec(name: "dismiss", parameters: []))
            #expect(specs[1] == ActionCaseSpec(
                name: "select",
                parameters: [ActionParam(label: nil, type: "Int")]
            ))
            #expect(specs[2] == ActionCaseSpec(
                name: "setColor",
                parameters: [ActionParam(label: "color", type: "String")]
            ))
        }
    }

    @Test("Nested enum by dotted name matches only within the enclosing type")
    func nestedDottedName() throws {
        try withSource(
            """
            struct Feature {
                enum Action { case tap }
            }
            struct Other {
                enum Action { case wrongOne }
            }
            """
        ) { dir in
            let specs = ActionAlphabetScanner.scan(directory: dir, actionTypeName: "Feature.Action")
            #expect(specs.map(\.name) == ["tap"])
        }
    }

    @Test("Unknown action type → empty (best-effort)")
    func unknownType() throws {
        try withSource("enum AppAction { case a }") { dir in
            #expect(ActionAlphabetScanner.scan(directory: dir, actionTypeName: "Nope").isEmpty)
        }
    }

    @Test("Missing directory → empty, never throws")
    func missingDirectory() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        #expect(ActionAlphabetScanner.scan(directory: dir, actionTypeName: "AppAction").isEmpty)
    }
}
