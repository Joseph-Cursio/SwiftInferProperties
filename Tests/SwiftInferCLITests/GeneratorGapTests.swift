import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Two of the generator gaps measured on SwiftLintRuleStudioCore, where 16 of 34 accepted stubs
/// type-checked before these changes and 22 of 33 after:
///
/// - a seed-synthesized law over a method on a **class** drew its receiver from a `.todo`
///   generator (`MigrationAssistant.gen()`), though the package's tests write
///   `MigrationAssistant()`; it is now held at that construction, inside the property closure;
/// - a stub calling `Gen<URL>.url()` failed with *no member 'url'* on a package resolving
///   SwiftPropertyLaws 3.3.0, for a generator added in 3.10.0; accept now says so.
@Suite("Generator gaps — held class receivers for seed laws, and the kit's version floor")
struct GeneratorGapTests {

    private struct Silent: DiagnosticOutput {
        func writeDiagnostic(_: String) { /* no-op */ }
    }

    private static let source = """
        public final class Assistant {
            public init() {}
            public func plan(_ ids: [String], from version: String) -> [String] { ids }
            public func apply(_ id: String, to config: inout [String]) { config.append(id) }
        }
        """

    /// The laws `discover --seeds` synthesizes for `symbol`, with `kind`.
    private static func laws(for symbol: String, kind: SeedKind) throws -> [Suggestion] {
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Assistant.swift")
        let summary = try #require(corpus.summaries.first { $0.name == symbol })
        let seed = SeedManifest.Seed(
            file: "Assistant.swift", line: 1, symbol: symbol, kind: kind,
            mutates: kind == .pureMutator ? "config" : nil
        )
        let manifest = SeedManifest(seeds: [seed])
        return SwiftInferCommand.Discover.synthesizeGenericLaws(
            for: manifest, summaries: [summary], covered: [], diagnostics: Silent()
        ) + SwiftInferCommand.Discover.synthesizeMutatorLaws(
            for: manifest, summaries: [summary], covered: [], diagnostics: Silent()
        )
    }

    /// The tests' own constructions, as `ReceiverConstructionSource` would harvest them.
    private static func constructed(_ typeName: String) -> String? {
        typeName == "Assistant" ? "Assistant()" : nil
    }

    // MARK: - Held receivers for the seed laws

    @Test("a determinism law over a class method is held at the tests' construction")
    func determinismIsHeld() throws {
        let law = try #require(try Self.laws(for: "plan", kind: .pureFunction).first)
        let held = try #require(HeldReceiver.rewriteSeedLaw(law, receiverExpression: Self.constructed))
        let stub = try #require(InteractiveTriage.deterministicStub(for: held))
        #expect(stub.contains("Assistant().plan(args.0, from: args.1)"), "got:\n\(stub)")
        #expect(stub.contains("Assistant.gen()") == false)
    }

    @Test("a mutator law over a class method is held, and still writes through &")
    func mutatorIsHeld() throws {
        let law = try #require(try Self.laws(for: "apply", kind: .pureMutator)
            .first { $0.templateName == "mutator-idempotence" })
        let held = try #require(HeldReceiver.rewriteSeedLaw(law, receiverExpression: Self.constructed))
        let stub = try #require(InteractiveTriage.mutatorStub(for: held))
        #expect(stub.contains("var once = args.1; Assistant().apply(args.0, to: &once)"), "got:\n\(stub)")
    }

    @Test("not held: no construction the tests write, or a template law the arity path owns")
    func notHeld() throws {
        let law = try #require(try Self.laws(for: "plan", kind: .pureFunction).first)
        #expect(HeldReceiver.rewriteSeedLaw(law) { _ in nil } == nil)
        var template = law
        template.templateName = "idempotence"
        #expect(HeldReceiver.rewriteSeedLaw(template, receiverExpression: Self.constructed) == nil)
    }

    // MARK: - The kit's version floor

    @Test("a stub calling a generator newer than the resolved kit names the release and the update")
    func floorIsNamed() throws {
        let stub = "sample: { rng in (Gen<URL>.url()).run(using: &rng) }"
        let note = try #require(KitAPIFloor.note(stub: stub, resolved: [3, 3, 0]))
        #expect(note.contains("`Gen<URL>.url()`, which SwiftPropertyLaws added in 3.10.0"))
        #expect(note.contains("this package resolves 3.3.0"))
        #expect(note.contains("swift package update SwiftPropertyLaws"))
    }

    @Test("no note at or above the floor, or with nothing to compare")
    func noNote() {
        let stub = "Gen<URL>.url() Gen<Decimal>.decimal()"
        #expect(KitAPIFloor.note(stub: stub, resolved: [3, 11, 0]) == nil)
        #expect(KitAPIFloor.note(stub: stub, resolved: [4, 9, 3]) == nil)
        #expect(KitAPIFloor.note(stub: stub, resolved: nil) == nil)
        #expect(KitAPIFloor.note(stub: "Gen<Int>.int(in: 0...1)", resolved: [3, 0, 0]) == nil)
    }

    @Test("the highest unmet floor is the one named")
    func highestFloor() throws {
        let note = try #require(KitAPIFloor.note(stub: "Gen<URL>.url() Gen<Decimal>.decimal()", resolved: [3, 10, 0]))
        #expect(note.contains("added in 3.11.0"))
        #expect(note.contains("Gen<URL>") == false)
    }

    @Test("the resolved kit version is read from Package.resolved, v2 and v1")
    func readsPackageResolved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("KitFloor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Package.resolved")
        try #"{"pins":[{"identity":"swiftpropertylaws","state":{"version":"3.3.0"}}],"version":2}"#
            .write(to: file, atomically: true, encoding: .utf8)
        #expect(KitAPIFloor.resolvedVersion(packageRoot: root) == [3, 3, 0])
        try #"{"object":{"pins":[{"package":"SwiftPropertyLaws","state":{"version":"3.12.1"}}]},"version":1}"#
            .write(to: file, atomically: true, encoding: .utf8)
        #expect(KitAPIFloor.resolvedVersion(packageRoot: root) == [3, 12, 1])
        try #"{"pins":[{"identity":"swiftpropertylaws","state":{"branch":"main"}}],"version":2}"#
            .write(to: file, atomically: true, encoding: .utf8)
        #expect(KitAPIFloor.resolvedVersion(packageRoot: root) == nil)
    }
}
