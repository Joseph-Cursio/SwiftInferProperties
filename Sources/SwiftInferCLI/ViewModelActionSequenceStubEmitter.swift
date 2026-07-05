import Foundation
import SwiftInferCore

/// PROTOTYPE — the M1′ multi-step ViewModel interaction verifier
/// (Observable Carrier thread 1, Slice 3). Where
/// `ViewModelInvariantStubEmitter` does a single deterministic pass over
/// each action once, this emits the *materialized-enum* path: it lifts the
/// action alphabet into a synthetic `enum` + `drive(_:_:)`
/// (`ViewModelActionEnumEmitter`), draws random `[Action]` sequences from
/// the kit's `ActionSequenceFactory`, and — per trial — constructs a
/// **fresh live** view model, replays the whole prefix through `drive`, and
/// re-checks the invariant after every step. That reaches the ordered
/// interleavings (`add; select; remove`) a single pass can't.
///
/// The instance is reference-typed and mutated in place (no synthetic value
/// `State`); a fresh `probe` per trial keeps trials independent.
///
/// **Scope (this slice):** the *nullary* action surface — every lifted case
/// is payload-free, so the sequence generator is
/// `actionSequence(forCaseIterable:)` and needs no per-case payload
/// generator. A payloaded surface throws `.payloadedSurfaceUnsupported`
/// (composing a `Gen<Action>` from `ViewModelArgumentGenerator` per case is
/// Slice 3b). Emits the `VERIFY_*` marker contract `VerifyResult` consumes,
/// so it is a drop-in richer replacement for the single-pass emitter.
public enum ViewModelActionSequenceStubEmitter {

    public struct Inputs: Equatable, Sendable {
        public let typeName: String
        public let userModuleName: String
        /// The invariant predicate over a `probe` instance, re-checked after
        /// every action (e.g. `probe.selectedID == nil || probe.items...`).
        public let predicate: String
        public let actions: [ViewModelAction]
        public let sequenceCount: Int
        public let lengthLowerBound: Int
        public let lengthUpperBound: Int

        public init(
            typeName: String,
            userModuleName: String,
            predicate: String,
            actions: [ViewModelAction],
            sequenceCount: Int = 100,
            lengthLowerBound: Int = 0,
            lengthUpperBound: Int = 16
        ) {
            self.typeName = typeName
            self.userModuleName = userModuleName
            self.predicate = predicate
            self.actions = actions
            self.sequenceCount = sequenceCount
            self.lengthLowerBound = lengthLowerBound
            self.lengthUpperBound = lengthUpperBound
        }
    }

    public enum EmitError: Error, CustomStringConvertible, Equatable {
        /// The lifted surface has ≥1 payloaded case, so `forCaseIterable:`
        /// can't enumerate it. Slice 3b composes a `Gen<Action>` per case.
        case payloadedSurfaceUnsupported(enumName: String)
        /// No liftable (sync, non-throwing) actions — nothing to drive.
        case emptyActionSurface(typeName: String)

        public var description: String {
            switch self {
            case let .payloadedSurfaceUnsupported(enumName):
                return "ViewModelActionSequenceStubEmitter: '\(enumName)' has payloaded "
                    + "cases; the CaseIterable sequence path only supports a nullary "
                    + "surface (payloaded Gen<Action> composition is Slice 3b)."

            case let .emptyActionSurface(typeName):
                return "ViewModelActionSequenceStubEmitter: '\(typeName)' has no liftable "
                    + "(synchronous, non-throwing) actions to drive."
            }
        }
    }

    public static func emit(_ inputs: Inputs) throws -> String {
        let lifted = ViewModelActionEnumEmitter.emit(
            typeName: inputs.typeName,
            actions: inputs.actions
        )
        guard !lifted.lifted.isEmpty else {
            throw EmitError.emptyActionSurface(typeName: inputs.typeName)
        }
        guard lifted.isCaseIterable else {
            throw EmitError.payloadedSurfaceUnsupported(enumName: lifted.enumName)
        }
        return renderVerifier(inputs: inputs, lifted: lifted)
    }

    /// Assemble the full verifier source once the action surface has been
    /// validated as a non-empty, nullary (CaseIterable) alphabet. Built from
    /// column-0 blocks (header / enum+drive / verifier struct) joined with the
    /// codebase's line-block idiom, so no single function trips the length cap.
    private static func renderVerifier(
        inputs: Inputs,
        lifted: ViewModelActionEnumEmitter.Result
    ) -> String {
        [
            headerBlock(inputs: inputs, skipped: lifted.skipped),
            lifted.source,
            verifierStruct(inputs: inputs, enumName: lifted.enumName)
        ]
        .joined(separator: "\n\n")
    }

    private static func headerBlock(
        inputs: Inputs,
        skipped: [ViewModelActionEnumEmitter.Skipped]
    ) -> String {
        let skippedNote = skipped.isEmpty
            ? ""
            : "\n// Excluded from the action surface: "
                + skipped.map { "\($0.action) (\($0.reason.rawValue))" }
                    .joined(separator: ", ")
        return """
        // PROTOTYPE — auto-generated M1′ ViewModel interaction verifier.
        // Type: \(inputs.typeName)
        // Invariant (after every action): \(inputs.predicate)\(skippedNote)
        import Foundation
        import \(inputs.userModuleName)
        import PropertyBased
        import PropertyLawKit
        """
    }

    private static func verifierStruct(inputs: Inputs, enumName: String) -> String {
        let length = "\(inputs.lengthLowerBound)...\(inputs.lengthUpperBound)"
        return """
        @main
        struct ViewModelInteractionVerifier {
            static func main() {
                var rng = Xoshiro(seed: (\(seedTuple(from: inputs.typeName))))
                let generator = ActionSequenceFactory.actionSequence(
                    forCaseIterable: \(enumName).self,
                    length: \(length)
                )
                var clean = 0
                for trial in 0..<\(inputs.sequenceCount) {
                    let actions = generator.run(using: &rng)
                    let probe = \(inputs.typeName)()
                    if !(\(inputs.predicate)) { report(fail: trial); return }
                    for action in actions {
                        drive(probe, action)
                        if !(\(inputs.predicate)) { report(fail: trial); return }
                    }
                    clean += 1
                }
                report(passTrials: clean)
            }
        \(Self.reportHelpers)
        }
        """
    }

    /// The two `VERIFY_*` marker reporters — static text, hoisted to a
    /// type-scope constant so `verifierStruct` stays within the length cap.
    /// Indented 4 spaces to sit inside the emitted struct body.
    private static let reportHelpers = """
            static func report(fail trial: Int) {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                exit(1)
            }

            static func report(passTrials trials: Int) {
                print("VERIFY_DEFAULT_RESULT: PASS")
                print("VERIFY_DEFAULT_TRIALS: \\(trials)")
                print("VERIFY_EDGE_RESULT: PASS")
                print("VERIFY_EDGE_TRIALS: 0")
                print("VERIFY_EDGE_SAMPLED: 0")
                exit(0)
            }
        """

    // MARK: - Deterministic seed

    /// Four byte-stable Xoshiro lanes derived from the type name via FNV-1a,
    /// so re-emitting a verifier for the same view model produces the same
    /// sequences (the "regeneration as diff" guarantee). `SipHasher` in the
    /// reducer emitter is `private`, so this keeps a self-contained hash
    /// rather than widening that type's access.
    static func seedTuple(from name: String) -> String {
        let lanes = ["a", "b", "c", "d"].map { salt in
            "0x" + String(fnv1a(name + "." + salt), radix: 16)
        }
        return lanes.joined(separator: ", ")
    }

    private static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash | 1 // Xoshiro state must not be all-zero.
    }
}
