import Foundation
import PropertyLawCore
import SwiftInferCore

/// Lets a stub draw a project type that is not `Sendable`, by declaring it `@unchecked Sendable`
/// once, in one generated file per test target.
///
/// `PropertyBackend.check` requires `Input: Sendable`, and Swift never infers `Sendable` for a
/// `public` type or for a class. So a `public struct Rec { let key: Int }` — as safe to share as a
/// value gets — could not be a check's input, and blocked every stub drawing it (15 equivalence
/// stubs in one census repository), and a non-`Sendable` class could get no generator at all
/// (91 set-aside markers in the seventh corpus census).
///
/// **Sound for the use it is put to.** A check draws a fresh value per trial and runs its trials
/// one after another, so nothing drawn is shared across threads; the conformance states what the
/// check already guarantees. It lives in the TEST target, so the type's own module is unchanged.
///
/// Measured on a fixture before building: the conformance compiles with no attribute for a type in
/// the same package (`@retroactive` is an error there), and restating it for a type that is
/// already `Sendable` — explicitly or by inference — is a warning, not an error. Declaring it
/// twice in one module IS an error, which is why every stub's types go into the one file.
enum SendableShim {

    /// The file every shim in a test target lives in, beside the generated stubs.
    static func fileURL(generatedRoot: URL) -> URL {
        generatedRoot.appendingPathComponent("SwiftInfer/SwiftInferSendableShims.swift")
    }

    /// Qualified names of the types a test file can name: visible to `@testable import`, and inside
    /// enclosing types that all are. A shim naming anything else would break the whole target.
    static func testVisibleTypeNames(from typeDecls: [TypeDecl]) -> Set<String> {
        let primaries = typeDecls.filter { $0.kind != .extension && $0.kind != .protocol }
        let visible = Set(primaries.filter(\.isVisibleToTestableImport).map(\.qualifiedName))
        let hidden = Set(primaries.filter { !$0.isVisibleToTestableImport }.map(\.qualifiedName))
        return visible.filter { name in
            let parts = name.split(separator: ".").map(String.init)
            return parts.indices.dropLast().allSatisfy { index in
                !hidden.contains(parts[...index].joined(separator: "."))
            }
        }
    }

    /// The shimmable project types named in `spelling` — `Rec`, `[Rec]`, `Rec?`, `[String: Rec]`.
    ///
    /// A type is shimmable when it is test-visible, is not an actor (calling into one needs
    /// `await`, which no stub emits), and does not already declare `Sendable` anywhere
    /// (`inheritedTypes` merges cross-file extensions, where conformances usually live).
    static func types(
        in spelling: String,
        visible: Set<String>,
        shapes: [String: TypeShape],
        inheritedTypes: [String: Set<String>]
    ) -> Set<String> {
        let identifier = /[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*/
        let names = spelling.matches(of: identifier).map { String($0.output) }
        return Set(names.filter { name in
            guard visible.contains(name), shapes[name]?.kind != .actor else { return false }
            let declared = inheritedTypes[name] ?? Set(shapes[name]?.inheritedTypes ?? [])
            return !declared.contains { isSendable($0) }
        })
    }

    /// Classes the kit may derive through their initializer because a shim will make them
    /// `Sendable` — presented to it as `@unchecked Sendable`, which kit 4.9.0 accepts.
    static func presentingShimmableClasses(_ shapes: [TypeShape], visible: Set<String>) -> [TypeShape] {
        shapes.map { shape in
            guard shape.kind == .class, visible.contains(shape.name), !shape.isSendableClass else { return shape }
            return TypeShape(
                name: shape.name,
                kind: shape.kind,
                inheritedTypes: shape.inheritedTypes + ["@unchecked Sendable"],
                hasUserGen: shape.hasUserGen,
                storedMembers: shape.storedMembers,
                hasUserInit: shape.hasUserInit,
                initializers: shape.initializers,
                enumCases: shape.enumCases,
                accessLevel: shape.accessLevel,
                hasPrimaryDeclaration: shape.hasPrimaryDeclaration
            )
        }
    }

    /// The shim file with `types` and `modules` merged into whatever it already declares, one
    /// extension per type, sorted, so rewriting it is idempotent and order-independent. Every
    /// module is imported by its Swift module name (`InteractiveTriage.moduleIdentifier`): the
    /// first census that wrote shims emitted `@testable import swift-assist-cli`, which does not
    /// parse and took its whole test target down.
    static func merged(existing: String?, adding types: Set<String>, modules adding: Set<String>) -> String {
        let lines = existing?.split(separator: "\n").map(String.init) ?? []
        let known = Set(lines.compactMap { line in
            line.wholeMatch(of: /extension (.+): @unchecked Sendable \{\}/).map { String($0.1) }
        })
        let modules = Set(lines.compactMap { line in
            line.wholeMatch(of: /@testable import (.+)/).map { String($0.1) }
        } + adding.map(InteractiveTriage.moduleIdentifier(from:)))
        let header = """
            // Auto-generated by `swift-infer discover --interactive` — do not edit.
            //
            // `PropertyBackend.check` requires its inputs to be `Sendable`, and Swift infers that for
            // neither a `public` type nor a class. Each type below is drawn by a generated stub; a
            // check draws a fresh value per trial and runs its trials in sequence, so nothing is
            // shared across threads. The conformances live here, in the test target only.
            """
        let imports = modules.sorted().map { "@testable import \($0)" }
        let extensions = known.union(types).sorted().map { "extension \($0): @unchecked Sendable {}" }
        return ([header, ""] + imports + [""] + extensions).joined(separator: "\n") + "\n"
    }

    private static func isSendable(_ inherited: String) -> Bool {
        let words = inherited.split(whereSeparator: \.isWhitespace).map(String.init)
        let bare = words.first == "@unchecked" ? Array(words.dropFirst()) : words
        return bare == ["Sendable"] || bare == ["Swift.Sendable"]
    }
}

/// The type spellings a stub asked a generator for, collected while the stub is built. A class so
/// the recording closure, which the emitters capture and call, can add to it.
final class DrawnTypeRecorder {
    private(set) var typeNames: Set<String> = []

    func record(_ typeName: String) {
        typeNames.insert(typeName)
    }
}

extension InteractiveTriage {

    /// `customGenerator(for:)`, recording every project type a stub asks it for, so the ones a
    /// check will draw can be made `Sendable` in the target's shim file once the stub is written.
    static func recordingGenerator(for context: Context) -> ((String) -> String?, DrawnTypeRecorder) {
        let drawn = DrawnTypeRecorder()
        let resolve = customGenerator(for: context)
        let recording: (String) -> String? = { typeName in
            let generator = resolve(typeName)
            if generator != nil { drawn.record(typeName) }
            return generator
        }
        return (recording, drawn)
    }

    /// Merge the shimmable project types among `typeNames` into the target's shim file. Writes
    /// nothing when none is shimmable, so a target whose stubs draw only `Sendable` values gets
    /// no file.
    static func writeSendableShims(for typeNames: Set<String>, context: Context) throws {
        let shimmable = typeNames.reduce(into: Set<String>()) { result, spelling in
            result.formUnion(SendableShim.types(
                in: spelling,
                visible: context.testVisibleTypeNames,
                shapes: context.typeShapesByName,
                inheritedTypes: context.inheritedTypesByName
            ))
        }
        guard !shimmable.isEmpty else { return }
        let url = SendableShim.fileURL(generatedRoot: context.generatedRoot)
        let existing = try? String(contentsOf: url, encoding: .utf8)
        // Each type's DECLARING module, as the stubs resolve theirs, then the run's module.
        let modules = Set(shimmable.compactMap { name in
            context.sourceFileByTypeName[name].flatMap(moduleName(fromSourceFile:))
        } + [context.moduleUnderTest].compactMap(\.self))
        let merged = SendableShim.merged(existing: existing, adding: shimmable, modules: modules)
        guard merged != existing else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(merged.utf8).write(to: url, options: .atomic)
    }
}
