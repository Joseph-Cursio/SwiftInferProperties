import Foundation

/// Errors from the package-based `known-properties` verify path.
enum KnownPropertiesVerifyError: Error, CustomStringConvertible {
    case unmappedModule(String)
    case buildFailed(String)

    var description: String {
        switch self {
        case let .unmappedModule(module):
            return "known-properties: no package mapping for module '\(module)' "
                + "(add it to KnownPropertiesPackages.byModule)"

        case let .buildFailed(detail):
            return "known-properties: package verify build failed — \(detail)"
        }
    }
}

/// The Apple / Swift first-party packages a `known-properties` law can import to
/// verify — the module → package-dependency mapping the package-based `--verify`
/// path uses to declare a temp SwiftPM package's dependencies.
///
/// Standard-library + `Foundation` laws carry no imports and run in the fast
/// `swift` interpreter (`KnownPropertiesCommand.runSwiftScript`); a law with
/// `imports` (e.g. `["DequeModule"]`) routes through the package path, which
/// declares the packages named here and builds against the **real** releases —
/// so every external law is genuinely executed, not asserted.
enum KnownPropertiesPackages {

    /// One SwiftPM package dependency, plus the product a module resolves to.
    struct Dependency: Equatable, Sendable {
        /// The package identity SwiftPM derives from the URL (`swift-collections`),
        /// used in `.product(name:package:)`.
        let packageIdentity: String
        let url: String
        /// The version requirement clause, e.g. `from: "1.1.0"`.
        let requirement: String
        /// The product to link for this module (often equal to the module name).
        let productName: String
    }

    /// Module name → the package + product that provides it. Every module a law
    /// lists in `imports` must appear here, or the package verify can't declare
    /// the dependency (surfaced as a clear error rather than a silent skip).
    static let byModule: [String: Dependency] = {
        let numerics = "https://github.com/apple/swift-numerics.git"
        let collections = "https://github.com/apple/swift-collections.git"
        let algorithms = "https://github.com/apple/swift-algorithms.git"
        func dep(_ identity: String, _ url: String, _ requirement: String, _ product: String) -> Dependency {
            Dependency(packageIdentity: identity, url: url, requirement: requirement, productName: product)
        }
        return [
            // swift-numerics (already resolved transitively via the kit).
            "ComplexModule": dep("swift-numerics", numerics, "from: \"1.0.0\"", "ComplexModule"),
            "RealModule": dep("swift-numerics", numerics, "from: \"1.0.0\"", "RealModule"),
            "Numerics": dep("swift-numerics", numerics, "from: \"1.0.0\"", "Numerics"),
            // swift-collections.
            "DequeModule": dep("swift-collections", collections, "from: \"1.1.0\"", "DequeModule"),
            "OrderedCollections": dep("swift-collections", collections, "from: \"1.1.0\"", "OrderedCollections"),
            "HashTreeCollections": dep("swift-collections", collections, "from: \"1.1.0\"", "HashTreeCollections"),
            "BitCollections": dep("swift-collections", collections, "from: \"1.1.0\"", "BitCollections"),
            "HeapModule": dep("swift-collections", collections, "from: \"1.1.0\"", "HeapModule"),
            "Collections": dep("swift-collections", collections, "from: \"1.1.0\"", "Collections"),
            // swift-algorithms.
            "Algorithms": dep("swift-algorithms", algorithms, "from: \"1.2.0\"", "Algorithms")
        ]
    }()

    /// The distinct package dependencies + the products to link, for a set of
    /// imported modules. Throws `unmappedModule` naming any module with no entry.
    static func resolve(modules: Set<String>) throws -> (packages: [Dependency], products: [(String, String)]) {
        var products: [(module: String, package: String)] = []
        var packagesByIdentity: [String: Dependency] = [:]
        for module in modules.sorted() {
            guard let dependency = byModule[module] else {
                throw KnownPropertiesVerifyError.unmappedModule(module)
            }
            products.append((dependency.productName, dependency.packageIdentity))
            packagesByIdentity[dependency.packageIdentity] = dependency
        }
        let packages = packagesByIdentity.values.sorted { $0.packageIdentity < $1.packageIdentity }
        return (packages, products)
    }
}
