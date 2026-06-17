import Foundation
import Testing

@testable import SwiftInferCLI

/// V1.42.C.3 — VerifierWorkdir synthesis unit tests.
///
/// Pins the rendered `Package.swift` structure + the `main.swift`
/// dropping. Subprocess invocation (`swift build` + binary spawn) is
/// integration territory and ships in V1.42.D.
@Suite("VerifierWorkdir — V1.42.C.3 synthesis")
struct VerifierWorkdirTests {

    // MARK: - Helpers

    private func makeTempDirectory() throws -> URL {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("verifier-workdir-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }

    private func cleanUp(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - synthesize(...)

    @Test("synthesize writes Package.swift + main.swift inside the workdir")
    func synthesizeWritesExpectedFiles() throws {
        let workdir = try makeTempDirectory()
        defer { cleanUp(workdir) }
        let mainPath = try VerifierWorkdir.synthesize(VerifierWorkdir.Inputs(
            workdir: workdir,
            userPackage: nil,
            stubSource: "// stub source"
        ))
        let packagePath = workdir.appendingPathComponent("Package.swift")
        #expect(FileManager.default.fileExists(atPath: packagePath.path))
        #expect(FileManager.default.fileExists(atPath: mainPath.path))
        #expect(mainPath.path.hasSuffix("Sources/SwiftInferVerifier/main.swift"))
    }

    @Test("synthesize writes the supplied stub source verbatim")
    func synthesizePreservesStubSource() throws {
        let workdir = try makeTempDirectory()
        defer { cleanUp(workdir) }
        let stub = "print(\"hello, verifier\")"
        let mainPath = try VerifierWorkdir.synthesize(VerifierWorkdir.Inputs(
            workdir: workdir,
            userPackage: nil,
            stubSource: stub
        ))
        let written = try String(contentsOf: mainPath, encoding: .utf8)
        #expect(written == stub)
    }

    @Test("synthesize is idempotent — second call overwrites without errors")
    func synthesizeIsIdempotent() throws {
        let workdir = try makeTempDirectory()
        defer { cleanUp(workdir) }
        let firstInputs = VerifierWorkdir.Inputs(
            workdir: workdir,
            userPackage: nil,
            stubSource: "// first"
        )
        let secondInputs = VerifierWorkdir.Inputs(
            workdir: workdir,
            userPackage: nil,
            stubSource: "// second"
        )
        _ = try VerifierWorkdir.synthesize(firstInputs)
        let mainPath = try VerifierWorkdir.synthesize(secondInputs)
        let written = try String(contentsOf: mainPath, encoding: .utf8)
        #expect(written == "// second")
    }

    @Test("Cycle 122 — .interactionTCA direct source inclusion: Verifier.swift + co-compiled corpus")
    func tcaDirectSourceInclusion() throws {
        let workdir = try makeTempDirectory()
        defer { cleanUp(workdir) }
        let stubPath = try VerifierWorkdir.synthesize(VerifierWorkdir.Inputs(
            workdir: workdir,
            userPackage: nil,
            stubSource: "// @main stub",
            mode: .interactionTCA,
            inlinedSources: [
                .init(name: "Counter.swift", contents: "// reducer source")
            ]
        ))
        // Stub is Verifier.swift (NOT main.swift) so @main + the co-compiled
        // corpus don't trip the top-level-code conflict.
        #expect(stubPath.path.hasSuffix("Sources/SwiftInferVerifier/Verifier.swift"))
        let corpus = workdir
            .appendingPathComponent("Sources/SwiftInferVerifier/Counter.swift")
        #expect(FileManager.default.fileExists(atPath: corpus.path))
        #expect(try String(contentsOf: corpus, encoding: .utf8) == "// reducer source")
        // No main.swift written.
        let mainPath = workdir.appendingPathComponent("Sources/SwiftInferVerifier/main.swift")
        #expect(!FileManager.default.fileExists(atPath: mainPath.path))
    }

    @Test("Cycle 122 — .interactionTCA Package.swift declares ComposableArchitecture, no user path dep")
    func tcaPackageDeclaresCA() {
        let rendered = VerifierWorkdir.renderPackageSwift(userPackage: nil, mode: .interactionTCA)
        #expect(rendered.contains("swift-composable-architecture"))
        #expect(rendered.contains(
            ".product(name: \"ComposableArchitecture\", package: \"swift-composable-architecture\")"
        ))
        #expect(rendered.contains(".product(name: \"PropertyLawKit\", package: \"SwiftPropertyLaws\")"))
        // Direct source inclusion → no `.package(path:)` user dependency.
        #expect(!rendered.contains(".package(path:"))
    }

    @Test(".interactionMobius Package.swift pins MobiusCore to the master revision, no user path dep")
    func mobiusPackageDeclaresMobiusRevision() {
        let rendered = VerifierWorkdir.renderPackageSwift(userPackage: nil, mode: .interactionMobius)
        #expect(rendered.contains("https://github.com/spotify/Mobius.swift.git"))
        // Pinned to the unreleased master commit (tagged releases don't build
        // under the current toolchain).
        #expect(rendered.contains("revision: \"74baa7e07b86ae4c2673204a92230db397b8a6ae\""))
        #expect(rendered.contains(".product(name: \"MobiusCore\", package: \"Mobius.swift\")"))
        #expect(!rendered.contains(".package(path:"))
    }

    // MARK: - renderPackageSwift(...)

    @Test("Package.swift without user package depends only on the kit deps")
    func packageSwiftWithoutUserPackage() {
        let rendered = VerifierWorkdir.renderPackageSwift(userPackage: nil)
        #expect(rendered.contains("// swift-tools-version: 6.1"))
        #expect(rendered.contains("name: \"SwiftInferVerifier\""))
        #expect(rendered.contains("swift-numerics"))
        #expect(rendered.contains("swift-property-based"))
        #expect(rendered.contains("SwiftPropertyLaws"))
        #expect(!rendered.contains(".package(path:"))
    }

    @Test("Package.swift with user package includes the local-path dep + product")
    func packageSwiftWithUserPackage() {
        let userPath = URL(fileURLWithPath: "/tmp/MyPackage")
        let userRef = VerifierWorkdir.UserPackageReference(
            packagePath: userPath,
            packageDeclaredName: "MyPackage",
            productNames: ["MyLib"]
        )
        let rendered = VerifierWorkdir.renderPackageSwift(userPackage: userRef)
        #expect(rendered.contains(".package(path: \"/tmp/MyPackage\")"))
        #expect(rendered.contains(".product(name: \"MyLib\", package: \"MyPackage\")"))
    }

    @Test("Package.swift always depends on the four mandatory products")
    func packageSwiftMandatoryProducts() {
        let rendered = VerifierWorkdir.renderPackageSwift(userPackage: nil)
        #expect(rendered.contains(".product(name: \"ComplexModule\""))
        #expect(rendered.contains(".product(name: \"RealModule\""))
        #expect(rendered.contains(".product(name: \"PropertyBased\""))
        #expect(rendered.contains(".product(name: \"PropertyLawComplex\", package: \"SwiftPropertyLaws\")"))
    }

    @Test("escapedLiteral escapes backslashes and double quotes")
    func escapedLiteralHandlesSpecialChars() {
        #expect(VerifierWorkdir.escapedLiteral("/tmp/foo") == "\"/tmp/foo\"")
        #expect(VerifierWorkdir.escapedLiteral("/a/path\\with") == "\"/a/path\\\\with\"")
        #expect(VerifierWorkdir.escapedLiteral("with\"quote") == "\"with\\\"quote\"")
    }

    // MARK: - V2.0 M3.E.2 — interaction mode

    @Test("default mode is .algebraic — v1.42 callers don't break")
    func defaultModeIsAlgebraic() {
        let rendered = VerifierWorkdir.renderPackageSwift(userPackage: nil)
        // The .algebraic shape includes numerics + collections; .interaction omits them.
        #expect(rendered.contains("swift-numerics"))
        #expect(rendered.contains("swift-collections"))
        #expect(rendered.contains("SwiftPropertyLaws.git\", from: \"2.1.0\""))
    }

    @Test(".interaction mode declares v2.2.0 kit + PropertyLawKit; omits numerics / collections")
    func interactionModeDeps() {
        let rendered = VerifierWorkdir.renderPackageSwift(userPackage: nil, mode: .interaction)
        #expect(rendered.contains("SwiftPropertyLaws.git\", from: \"2.2.0\""))
        #expect(rendered.contains("swift-property-based"))
        #expect(!rendered.contains("swift-numerics"))
        #expect(!rendered.contains("swift-collections"))
    }

    @Test(".interaction mode target deps are PropertyBased + PropertyLawKit only")
    func interactionModeTargetDeps() {
        let rendered = VerifierWorkdir.renderPackageSwift(userPackage: nil, mode: .interaction)
        #expect(rendered.contains(".product(name: \"PropertyBased\""))
        #expect(rendered.contains(".product(name: \"PropertyLawKit\", package: \"SwiftPropertyLaws\")"))
        // Algebraic-only products must NOT appear.
        #expect(!rendered.contains("ComplexModule"))
        #expect(!rendered.contains("RealModule"))
        #expect(!rendered.contains("PropertyLawComplex"))
    }

    @Test(".interaction mode preserves the user-package dep + products when supplied")
    func interactionModeWithUserPackage() {
        let userRef = VerifierWorkdir.UserPackageReference(
            packagePath: URL(fileURLWithPath: "/tmp/MyApp"),
            packageDeclaredName: "MyApp",
            productNames: ["MyAppLib"]
        )
        let rendered = VerifierWorkdir.renderPackageSwift(
            userPackage: userRef,
            mode: .interaction
        )
        #expect(rendered.contains(".package(path: \"/tmp/MyApp\")"))
        #expect(rendered.contains(".product(name: \"MyAppLib\", package: \"MyApp\")"))
        #expect(rendered.contains(".product(name: \"PropertyLawKit\""))
    }

    @Test("WorkdirMode rawValues are stable strings")
    func workdirModeRawValues() {
        #expect(WorkdirMode.algebraic.rawValue == "algebraic")
        #expect(WorkdirMode.interaction.rawValue == "interaction")
        #expect(WorkdirMode.interactionTCA.rawValue == "interaction-tca")
        #expect(WorkdirMode.interactionMobius.rawValue == "interaction-mobius")
        #expect(WorkdirMode.allCases.count == 4)
    }
}
