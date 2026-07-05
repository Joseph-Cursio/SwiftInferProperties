import Foundation
import PropertyLawCore
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
/// **Scope.** An all-nullary surface enumerates directly via
/// `actionSequence(forCaseIterable:)`. A payloaded surface composes a
/// `Gen<Action>` (Slice 3b) over the *constructible* subset — payload-free
/// cases (`Gen.always(.case)`) and single raw-scalar payloads
/// (`<RawType gen>.map(Enum.case)`, mirroring the reducer path's
/// `tcaActionGenLines`). Non-constructible cases (multi-arg, or a non-raw
/// single payload such as `UUID` / a model type) are **disclosed** in the
/// header and left out of exploration, not silently dropped — the same
/// partial-exploration posture as the `.tca` path. A surface with *no*
/// constructible case throws `.noConstructibleActions`. Emits the `VERIFY_*`
/// marker contract `VerifyResult` consumes, so it is a drop-in richer
/// replacement for the single-pass emitter.
public enum ViewModelActionSequenceStubEmitter {

    public struct Inputs: Equatable, Sendable {
        public let typeName: String
        /// The module to `import` for the view model type, or `nil` when the
        /// model is compiled **into** the verifier target (same-target inlined
        /// verification — `VerifierWorkdir`'s `inlinedSources` shape), where no
        /// import is needed and one would fail to resolve.
        public let userModuleName: String?
        /// The invariant predicate over a `probe` instance, re-checked after
        /// every action (e.g. `probe.selectedID == nil || probe.items...`).
        public let predicate: String
        public let actions: [ViewModelAction]
        public let sequenceCount: Int
        public let lengthLowerBound: Int
        public let lengthUpperBound: Int

        public init(
            typeName: String,
            userModuleName: String?,
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
        /// No liftable (sync, non-throwing) actions — nothing to drive.
        case emptyActionSurface(typeName: String)
        /// Every lifted case has a non-constructible payload (multi-arg, or a
        /// non-raw single payload), so no `Gen<Action>` can be composed.
        case noConstructibleActions(typeName: String)

        public var description: String {
            switch self {
            case let .emptyActionSurface(typeName):
                return "ViewModelActionSequenceStubEmitter: '\(typeName)' has no liftable "
                    + "(synchronous, non-throwing) actions to drive."

            case let .noConstructibleActions(typeName):
                return "ViewModelActionSequenceStubEmitter: '\(typeName)' has no constructible "
                    + "action — every case has a multi-arg or non-raw payload the generator "
                    + "can't produce."
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
        let plan = try generatorPlan(inputs: inputs, lifted: lifted)
        return renderVerifier(inputs: inputs, lifted: lifted, plan: plan)
    }

    // MARK: - Generator plan

    /// The `let generator = …` setup lines (8-space indented) plus the cases
    /// left out of exploration because their payload isn't generatable.
    private struct GeneratorPlan {
        let setup: [String]
        let excludedNonConstructible: [String]
    }

    private static func generatorPlan(
        inputs: Inputs,
        lifted: ViewModelActionEnumEmitter.Result
    ) throws -> GeneratorPlan {
        let length = "\(inputs.lengthLowerBound)...\(inputs.lengthUpperBound)"
        // All-nullary → the enum is CaseIterable; enumerate it directly.
        if lifted.isCaseIterable {
            return GeneratorPlan(
                setup: [
                    "        let generator = ActionSequenceFactory.actionSequence(",
                    "            forCaseIterable: \(lifted.enumName).self,",
                    "            length: \(length)",
                    "        )"
                ],
                excludedNonConstructible: []
            )
        }
        // Payloaded → compose a Gen<Action> over the constructible subset.
        var gens: [String] = []
        var excluded: [String] = []
        for liftedCase in lifted.lifted {
            if let gen = caseGenerator(enumName: lifted.enumName, liftedCase: liftedCase) {
                gens.append(gen)
            } else {
                excluded.append(liftedCase.action.name)
            }
        }
        guard !gens.isEmpty else {
            throw EmitError.noConstructibleActions(typeName: inputs.typeName)
        }
        var setup = actionGenLines(gens)
        setup.append("        let generator = ActionSequenceFactory.actionSequence(")
        setup.append("            from: actionGen,")
        setup.append("            length: \(length)")
        setup.append("        )")
        return GeneratorPlan(setup: setup, excludedNonConstructible: excluded)
    }

    /// `Gen.always(.case)` for a payload-free case; `<rawGen>.map(Enum.case)`
    /// for a single raw-scalar payload; `nil` (non-constructible) otherwise.
    private static func caseGenerator(
        enumName: String,
        liftedCase: ViewModelActionEnumEmitter.LiftedCase
    ) -> String? {
        let params = liftedCase.action.parameters
        if params.isEmpty {
            return "Gen.always(\(enumName).\(liftedCase.caseName))"
        }
        guard params.count == 1, let raw = RawType(typeName: params[0].typeText) else {
            return nil
        }
        return "\(raw.generatorExpression).map(\(enumName).\(liftedCase.caseName))"
    }

    /// `let actionGen = <gen>` (single) or a `Gen.oneOf(…)` block (8-space base).
    private static func actionGenLines(_ gens: [String]) -> [String] {
        if gens.count == 1 { return ["        let actionGen = \(gens[0])"] }
        var lines = ["        let actionGen = Gen.oneOf("]
        for (index, gen) in gens.enumerated() {
            lines.append("            \(gen)" + (index == gens.count - 1 ? "" : ","))
        }
        lines.append("        )")
        return lines
    }

    // MARK: - Rendering

    /// Assemble the verifier from column-0 blocks (header / enum+drive /
    /// verifier struct), joined with the codebase's line-block idiom so no
    /// single function trips the length cap.
    private static func renderVerifier(
        inputs: Inputs,
        lifted: ViewModelActionEnumEmitter.Result,
        plan: GeneratorPlan
    ) -> String {
        [
            headerBlock(inputs: inputs, lifted: lifted, plan: plan),
            lifted.source,
            verifierStruct(inputs: inputs, generatorSetup: plan.setup)
        ]
        .joined(separator: "\n\n")
    }

    private static func headerBlock(
        inputs: Inputs,
        lifted: ViewModelActionEnumEmitter.Result,
        plan: GeneratorPlan
    ) -> String {
        var excluded = lifted.skipped.map { "\($0.action) (\($0.reason.rawValue))" }
        excluded += plan.excludedNonConstructible.map { "\($0) (non-generatable payload)" }
        let note = excluded.isEmpty
            ? ""
            : "\n// Excluded from the action surface: " + excluded.joined(separator: ", ")
        // No user-module import when the model is inlined into this target.
        let userImport = inputs.userModuleName.map { "\nimport \($0)" } ?? ""
        return """
        // PROTOTYPE — auto-generated M1′ ViewModel interaction verifier.
        // Type: \(inputs.typeName)
        // Invariant (after every action): \(inputs.predicate)\(note)
        import Foundation\(userImport)
        import PropertyBased
        import PropertyLawKit
        """
    }

    private static func verifierStruct(inputs: Inputs, generatorSetup: [String]) -> String {
        var lines: [String] = [
            "@main",
            "struct ViewModelInteractionVerifier {",
            "    static func main() {",
            "        var rng = Xoshiro(seed: (\(seedTuple(from: inputs.typeName))))"
        ]
        lines.append(contentsOf: generatorSetup)
        lines.append(contentsOf: [
            "        var clean = 0",
            "        for trial in 0..<\(inputs.sequenceCount) {",
            "            let actions = generator.run(using: &rng)",
            "            let probe = \(inputs.typeName)()",
            "            if !(\(inputs.predicate)) { report(fail: trial); return }",
            "            for action in actions {",
            "                drive(probe, action)",
            "                if !(\(inputs.predicate)) { report(fail: trial); return }",
            "            }",
            "            clean += 1",
            "        }",
            "        report(passTrials: clean)",
            "    }",
            ""
        ])
        lines.append(contentsOf: Self.reportHelperLines)
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    /// The two `VERIFY_*` marker reporters (4-space indented, inside the emitted
    /// struct) — static text hoisted out so `verifierStruct` stays short.
    private static let reportHelperLines: [String] = [
        "    static func report(fail trial: Int) {",
        "        print(\"VERIFY_DEFAULT_RESULT: FAIL\")",
        "        print(\"VERIFY_DEFAULT_TRIAL: \\(trial)\")",
        "        exit(1)",
        "    }",
        "",
        "    static func report(passTrials trials: Int) {",
        "        print(\"VERIFY_DEFAULT_RESULT: PASS\")",
        "        print(\"VERIFY_DEFAULT_TRIALS: \\(trials)\")",
        "        print(\"VERIFY_EDGE_RESULT: PASS\")",
        "        print(\"VERIFY_EDGE_TRIALS: 0\")",
        "        print(\"VERIFY_EDGE_SAMPLED: 0\")",
        "        exit(0)",
        "    }"
    ]

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
