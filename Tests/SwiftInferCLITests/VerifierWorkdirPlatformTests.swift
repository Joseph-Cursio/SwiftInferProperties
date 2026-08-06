import Foundation
@testable import SwiftInferCLI
import Testing

/// The verifier's macOS deployment floor must agree with the corpus it links.
///
/// SwiftPM refuses to link an executable whose platform floor sits below a
/// product it depends on, so a mismatch is not a partial failure — it fails
/// *every* entry in a survey, and it fails them as `build-failed`, i.e. wearing
/// the costume of a tooling error rather than a version mismatch. Measured on
/// SwiftProjectLint before the floor was derived: 60 of 60 picks.
///
/// These tests pin the derivation rather than a number. A constant is what the
/// code had, and any constant is wrong for some corpus: raising it from 14 to 26
/// merely swaps which half of the world is broken.
@Suite("Verifier workdir — macOS floor is derived from the corpus")
struct VerifierWorkdirPlatformTests {

    // MARK: - Helpers

    /// Write a throwaway package whose manifest is `manifest`, and return a
    /// `UserPackageReference` pointing at it.
    private func makeCorpus(manifest: String) throws -> (URL, VerifierWorkdir.UserPackageReference) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("verifier-platform-tests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Corpus")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try manifest.write(
            to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8
        )
        return (root, VerifierWorkdir.UserPackageReference(packagePath: root, productNames: ["Corpus"]))
    }

    private func cleanUp(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: - Both spellings

    @Test("reads the enum spelling, .macOS(.v26)")
    func readsEnumSpelling() throws {
        let (root, reference) = try makeCorpus(
            manifest: "platforms: [.macOS(.v26), .iOS(.v26)],"
        )
        defer { cleanUp(root) }
        #expect(VerifierWorkdir.declaredMacOSVersion(inPackageAt: root) == "26.0")
        #expect(VerifierWorkdir.macOSPlatformLine(userPackage: reference) == ".macOS(\"26.0\")")
    }

    @Test("reads the string spelling, .macOS(\"26.0\")")
    func readsStringSpelling() throws {
        let (root, reference) = try makeCorpus(manifest: "platforms: [.macOS(\"26.0\")],")
        defer { cleanUp(root) }
        #expect(VerifierWorkdir.declaredMacOSVersion(inPackageAt: root) == "26.0")
        #expect(VerifierWorkdir.macOSPlatformLine(userPackage: reference) == ".macOS(\"26.0\")")
    }

    @Test("reads the string spelling without a minor component")
    func readsStringSpellingBareMajor() throws {
        let (root, _) = try makeCorpus(manifest: "platforms: [.macOS(\"15\")],")
        defer { cleanUp(root) }
        #expect(VerifierWorkdir.declaredMacOSVersion(inPackageAt: root) == "15.0")
    }

    // MARK: - Choosing among several

    /// The reason the comparison is numeric rather than a `max()` over the
    /// matched substrings: lexicographically `"9.0" > "14.0"`, which would pick
    /// a floor *below* the corpus and reintroduce the exact link failure this
    /// derivation exists to prevent.
    @Test("takes the highest declaration numerically, not lexicographically")
    func takesHighestNumerically() throws {
        let (root, _) = try makeCorpus(
            manifest: "platforms: [.macOS(.v9), .macOS(.v14)],"
        )
        defer { cleanUp(root) }
        #expect(VerifierWorkdir.declaredMacOSVersion(inPackageAt: root) == "14.0")
    }

    @Test("takes the highest across mixed spellings")
    func takesHighestAcrossSpellings() throws {
        let (root, _) = try makeCorpus(
            manifest: "platforms: [.macOS(.v13), .macOS(\"26.0\")],"
        )
        defer { cleanUp(root) }
        #expect(VerifierWorkdir.declaredMacOSVersion(inPackageAt: root) == "26.0")
    }

    // MARK: - Falling back

    @Test("a manifest declaring no macOS platform falls back to the default")
    func noDeclarationFallsBack() throws {
        let (root, reference) = try makeCorpus(manifest: "platforms: [.iOS(.v17)],")
        defer { cleanUp(root) }
        #expect(VerifierWorkdir.declaredMacOSVersion(inPackageAt: root) == nil)
        #expect(
            VerifierWorkdir.macOSPlatformLine(userPackage: reference)
                == ".macOS(\"\(VerifierWorkdir.defaultMacOSVersion)\")"
        )
    }

    @Test("an unreadable manifest falls back to the default")
    func unreadableManifestFallsBack() {
        let missing = URL(fileURLWithPath: "/nonexistent-corpus-\(UUID().uuidString)")
        #expect(VerifierWorkdir.declaredMacOSVersion(inPackageAt: missing) == nil)
    }

    /// No user package means no corpus to disagree with — the stdlib-carrier
    /// path, which worked on the old constant and must keep working on it.
    @Test("no user package keeps the previous constant")
    func noUserPackageKeepsConstant() {
        #expect(
            VerifierWorkdir.macOSPlatformLine(userPackage: nil)
                == ".macOS(\"\(VerifierWorkdir.defaultMacOSVersion)\")"
        )
        #expect(VerifierWorkdir.defaultMacOSVersion == "14.0")
    }

    // MARK: - Reaching the manifest

    @Test("the derived floor reaches the rendered Package.swift")
    func derivedFloorReachesManifest() throws {
        let (root, reference) = try makeCorpus(manifest: "platforms: [.macOS(.v26)],")
        defer { cleanUp(root) }
        let rendered = VerifierWorkdir.renderPackageSwift(userPackage: reference, mode: .algebraic)
        #expect(rendered.contains(".macOS(\"26.0\")"))
    }

    /// The generated manifest is `swift-tools-version: 6.1`, whose
    /// `PackageDescription` has no `.v26` — emitting the enum form fails with
    /// *'v26' is unavailable*. The string form is accepted at every tools
    /// version, so it is the only spelling that cannot rot as macOS advances.
    @Test("the floor is emitted in string form, never as a version enum case")
    func floorEmittedAsString() throws {
        let (root, reference) = try makeCorpus(manifest: "platforms: [.macOS(.v26)],")
        defer { cleanUp(root) }
        let rendered = VerifierWorkdir.renderPackageSwift(userPackage: reference, mode: .algebraic)
        #expect(!rendered.contains(".macOS(.v"))
    }
}
