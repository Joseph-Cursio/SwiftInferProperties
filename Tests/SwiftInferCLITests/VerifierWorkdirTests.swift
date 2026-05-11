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

    // MARK: - renderPackageSwift(...)

    @Test("Package.swift without user package depends only on the kit deps")
    func packageSwiftWithoutUserPackage() {
        let rendered = VerifierWorkdir.renderPackageSwift(userPackage: nil)
        #expect(rendered.contains("// swift-tools-version: 6.1"))
        #expect(rendered.contains("name: \"SwiftInferVerifier\""))
        #expect(rendered.contains("swift-numerics"))
        #expect(rendered.contains("swift-property-based"))
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

    @Test("Package.swift always depends on the three V1.42-mandatory products")
    func packageSwiftMandatoryProducts() {
        let rendered = VerifierWorkdir.renderPackageSwift(userPackage: nil)
        #expect(rendered.contains(".product(name: \"ComplexModule\""))
        #expect(rendered.contains(".product(name: \"RealModule\""))
        #expect(rendered.contains(".product(name: \"PropertyBased\""))
    }

    @Test("escapedLiteral escapes backslashes and double quotes")
    func escapedLiteralHandlesSpecialChars() {
        #expect(VerifierWorkdir.escapedLiteral("/tmp/foo") == "\"/tmp/foo\"")
        #expect(VerifierWorkdir.escapedLiteral("/a/path\\with") == "\"/a/path\\\\with\"")
        #expect(VerifierWorkdir.escapedLiteral("with\"quote") == "\"with\\\"quote\"")
    }
}
