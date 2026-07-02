import Foundation

/// Resolves the *library product* name that vends a given target module in a
/// user package. SwiftPM's `.product(name:package:)` dependency edge names a
/// **product**, but the carrier types the verifier `import`s live in a
/// **target (module)** — and the two names need not match. A package with
///
///     .library(name: "Foo", targets: ["FooCore"])
///
/// vends module `FooCore` through product `Foo`; the verifier workdir must
/// write `.product(name: "Foo", …)` while the stub does `import FooCore`.
/// Passing the module name as the product name (the pre-tier-2 behavior)
/// build-fails with "unknown product 'FooCore'".
///
/// This is the sibling of `UserPackageReference.packageIdentity` (which fixes
/// package-identity-vs-declared-name): together they cover the three distinct
/// names a `.package(path:)` + `.product(name:package:)` pair references —
/// package identity (path basename), product name (this type), and module
/// name (the stub's `import`).
///
/// Introspects via `swift package dump-package` — the authoritative manifest
/// evaluation. Degrades gracefully: any failure (dump errors, JSON shape
/// drift, module not vended by any library product) returns `nil`, and the
/// caller falls back to using the module name as the product name — the prior
/// behavior — so packages where product == module are unaffected.
public enum PackageProductResolver {

    private struct DumpedPackage: Decodable {
        let products: [DumpedProduct]
    }

    private struct DumpedProduct: Decodable {
        let name: String
        let targets: [String]
        let type: ProductType

        /// `type.library` is present (a `["automatic"]`/`["static"]`/`["dynamic"]`
        /// array) for library products; absent for executables/plugins, which
        /// can't be a cross-package `.product` dependency.
        var isLibrary: Bool { type.library != nil }
    }

    private struct ProductType: Decodable {
        let library: [String]?
    }

    /// The library product that vends `module`, or `nil` if none does (or the
    /// manifest can't be read). Preference order, restricted to products whose
    /// `targets` actually include `module` (so the resulting `import` resolves):
    ///   1. a product named exactly `module` (the common `product == module` case);
    ///   2. a single-target product `[module]` (an unambiguous 1:1 wrapper);
    ///   3. any vending product (lowest `name`, for determinism).
    /// Falls back to a library product *named* `module` even if `dump-package`
    /// didn't list the target directly (defensive; unlikely).
    public static func libraryProduct(
        exposingModule module: String,
        packageRoot: URL
    ) -> String? {
        guard let dumped = dump(packageRoot: packageRoot) else { return nil }
        let libraries = dumped.products.filter(\.isLibrary)
        let vending = libraries.filter { $0.targets.contains(module) }
        if let exact = vending.first(where: { $0.name == module }) { return exact.name }
        if let single = vending.first(where: { $0.targets == [module] }) { return single.name }
        if let any = vending.min(by: { $0.name < $1.name }) { return any.name }
        if libraries.contains(where: { $0.name == module }) { return module }
        return nil
    }

    /// Run `swift package dump-package --package-path <root>` and decode it.
    /// Returns `nil` on any failure (non-zero exit, undecodable output) so the
    /// caller degrades to the module-name-as-product-name fallback. Mirrors the
    /// `/usr/bin/env swift` resolution `VerifierSubprocess` uses so the same
    /// PATH-resolved toolchain that runs `swift build` evaluates the manifest.
    private static func dump(packageRoot: URL) -> DumpedPackage? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swift", "package", "dump-package", "--package-path", packageRoot.path
        ]
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        return try? JSONDecoder().decode(DumpedPackage.self, from: data)
    }
}
