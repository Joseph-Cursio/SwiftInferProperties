import ArgumentParser
import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// TestLifter M8.1 — pure-function engine behind
/// `swift-infer convert-counterexample`. Lifted out of
/// `ConvertCounterexampleCommand.swift` so the AsyncParsableCommand
/// shell stays small + the engine is unit-testable without going
/// through ArgumentParser's `parse(_:)`.
public enum ConvertCounterexampleEngine {

    /// Plain-old struct bundling the args the static helpers need.
    /// Tests construct this directly without going through
    /// ArgumentParser (which doesn't initialize `@Option` defaults
    /// when the type is constructed via `init()` rather than
    /// `parse(_:)`).
    public struct Args: Sendable, Equatable {
        public var template: String
        public var callee: String
        public var type: String
        public var counterexample: String
        public var reverseCallee: String?
        public var identityElement: String?
        public var seedSource: String?
        public var reduceElementType: String?
        public var invariantKeypath: String?

        public init(
            template: String,
            callee: String,
            type: String,
            counterexample: String,
            reverseCallee: String? = nil,
            identityElement: String? = nil,
            seedSource: String? = nil,
            reduceElementType: String? = nil,
            invariantKeypath: String? = nil
        ) {
            self.template = template
            self.callee = callee
            self.type = type
            self.counterexample = counterexample
            self.reverseCallee = reverseCallee
            self.identityElement = identityElement
            self.seedSource = seedSource
            self.reduceElementType = reduceElementType
            self.invariantKeypath = invariantKeypath
        }
    }

    public static let validTemplates: [String] = [
        "idempotence",
        "round-trip",
        "monotonicity",
        "invariant-preservation",
        "commutativity",
        "associativity",
        "identity-element",
        "inverse-pair",
        "count-invariance",
        "reduce-equivalence"
    ]

    // MARK: - Package-root walk-up

    public static func resolvePackageRoot(explicit: String?) throws -> URL {
        if let explicit {
            return URL(fileURLWithPath: explicit).standardizedFileURL
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if let walked = walkUpForPackageManifest(startingFrom: cwd) {
            return walked
        }
        throw ValidationError(
            "could not find Package.swift via walk-up from \(cwd.path);"
                + " pass --package-root <path> to override"
        )
    }

    private static func walkUpForPackageManifest(startingFrom directory: URL) -> URL? {
        let fileManager = FileManager.default
        var current = directory.standardizedFileURL
        while true {
            let manifest = current.appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: manifest.path) {
                return current
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent == current {
                return nil
            }
            current = parent
        }
    }

    // MARK: - Stub rendering — dispatch to LiftedTestEmitter regression arm

    public static func renderRegressionStub(args: Args) throws -> String {
        if let stub = try renderUnaryTemplate(args) {
            return stub
        }
        if let stub = try renderBinaryTemplate(args) {
            return stub
        }
        throw ValidationError(
            "unknown --template '\(args.template)';"
                + " valid: \(validTemplates.joined(separator: ", "))"
        )
    }

    /// Unary-shaped templates — single `value: T` input. Returns nil
    /// when `args.template` doesn't match any unary template; the
    /// caller falls through to `renderBinaryTemplate`.
    private static func renderUnaryTemplate(_ args: Args) throws -> String? {
        switch args.template {
        case "idempotence": return try renderIdempotence(args)
        case "round-trip": return try renderRoundTrip(args)
        case "invariant-preservation": return try renderInvariantPreservation(args)
        case "identity-element": return try renderIdentityElement(args)
        case "inverse-pair": return try renderInversePair(args)
        default: return nil
        }
    }

    /// Binary-/collection-shaped templates — pair / triple / `[T]`
    /// input. Returns nil when `args.template` doesn't match.
    private static func renderBinaryTemplate(_ args: Args) throws -> String? {
        switch args.template {
        case "monotonicity": return try renderMonotonicity(args)
        case "commutativity": return try renderCommutativity(args)
        case "associativity": return try renderAssociativity(args)
        case "count-invariance": return try renderCountInvariance(args)
        case "reduce-equivalence": return try renderReduceEquivalence(args)
        default: return nil
        }
    }

    private static func renderIdempotence(_ args: Args) throws -> String {
        LiftedTestEmitter.idempotentRegression(
            funcName: args.callee, typeName: args.type, inputSource: args.counterexample
        )
    }

    private static func renderRoundTrip(_ args: Args) throws -> String {
        LiftedTestEmitter.roundTripRegression(
            forwardName: args.callee,
            inverseName: try requireReverseCallee(args),
            typeName: args.type,
            inputSource: args.counterexample
        )
    }

    private static func renderMonotonicity(_ args: Args) throws -> String {
        LiftedTestEmitter.monotonicRegression(
            funcName: args.callee,
            tupleType: "(\(args.type), \(args.type))",
            inputSource: args.counterexample
        )
    }

    private static func renderInvariantPreservation(_ args: Args) throws -> String {
        LiftedTestEmitter.invariantPreservingRegression(
            funcName: args.callee,
            typeName: args.type,
            invariantName: try requireInvariantKeypath(args),
            inputSource: args.counterexample
        )
    }

    private static func renderCommutativity(_ args: Args) throws -> String {
        LiftedTestEmitter.commutativeRegression(
            funcName: args.callee,
            tupleType: "(\(args.type), \(args.type))",
            inputSource: args.counterexample
        )
    }

    private static func renderAssociativity(_ args: Args) throws -> String {
        LiftedTestEmitter.associativeRegression(
            funcName: args.callee,
            tripleType: "(\(args.type), \(args.type), \(args.type))",
            inputSource: args.counterexample
        )
    }

    private static func renderIdentityElement(_ args: Args) throws -> String {
        LiftedTestEmitter.identityElementRegression(
            funcName: args.callee,
            typeName: args.type,
            identityName: try requireIdentityName(args),
            inputSource: args.counterexample
        )
    }

    private static func renderInversePair(_ args: Args) throws -> String {
        LiftedTestEmitter.inversePairRegression(
            forwardName: args.callee,
            inverseName: try requireReverseCallee(args),
            typeName: args.type,
            inputSource: args.counterexample
        )
    }

    private static func renderCountInvariance(_ args: Args) throws -> String {
        LiftedTestEmitter.liftedCountInvarianceRegression(
            funcName: args.callee,
            elementTypeName: try requireReduceElementType(args),
            inputSource: args.counterexample
        )
    }

    private static func renderReduceEquivalence(_ args: Args) throws -> String {
        LiftedTestEmitter.liftedReduceEquivalenceRegression(
            opName: args.callee,
            elementTypeName: try requireReduceElementType(args),
            seedSource: try requireSeedSource(args),
            inputSource: args.counterexample
        )
    }

    // MARK: - File write — sandboxed at <package-root>/Tests/Generated/SwiftInfer/

    public static func writeRegressionStub(
        args: Args,
        stub: String,
        packageRoot: URL
    ) throws -> URL {
        let hash = LiftedTestEmitter.regressionFileHash(for: args.counterexample)
        let directory = packageRoot
            .appendingPathComponent("Tests/Generated/SwiftInfer")
            .appendingPathComponent(args.template)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let path = directory.appendingPathComponent("\(args.callee)_regression_\(hash).swift")
        let contents = wrappedFileContents(args: args, stub: stub, hash: hash)
        try Data(contents.utf8).write(to: path, options: .atomic)
        return path
    }

    private static func wrappedFileContents(args: Args, stub: String, hash: String) -> String {
        """
        // Auto-generated by `swift-infer convert-counterexample` — do not edit.
        // Counterexample for: \(args.template) / \(args.callee)
        // Counterexample source: \(args.counterexample)
        // SHA256 prefix: \(hash)

        import Testing
        \(stub)
        """
    }

    // MARK: - Per-template required-flag validation

    private static func requireReverseCallee(_ args: Args) throws -> String {
        guard let value = args.reverseCallee else {
            throw ValidationError(
                "--reverse-callee is required for --template '\(args.template)'"
            )
        }
        return value
    }

    private static func requireIdentityName(_ args: Args) throws -> String {
        guard let value = args.identityElement else {
            throw ValidationError(
                "--identity-element is required for --template 'identity-element'"
            )
        }
        return value
    }

    private static func requireReduceElementType(_ args: Args) throws -> String {
        guard let value = args.reduceElementType else {
            throw ValidationError(
                "--reduce-element-type is required for --template '\(args.template)'"
            )
        }
        return value
    }

    private static func requireSeedSource(_ args: Args) throws -> String {
        guard let value = args.seedSource else {
            throw ValidationError(
                "--seed-source is required for --template 'reduce-equivalence'"
            )
        }
        return value
    }

    private static func requireInvariantKeypath(_ args: Args) throws -> String {
        guard let value = args.invariantKeypath else {
            throw ValidationError(
                "--invariant-keypath is required for --template 'invariant-preservation'"
            )
        }
        return value
    }
}
