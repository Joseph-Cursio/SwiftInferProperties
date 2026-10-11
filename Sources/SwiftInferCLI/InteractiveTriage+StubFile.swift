import Foundation
import PropertyLawCore
import SwiftInferCore

extension InteractiveTriage {

    /// Wrap the bare `@Test func` block from `LiftedTestEmitter` with
    /// the file-level imports + provenance header for the
    /// `Tests/Generated/SwiftInfer/` writeout. Lifted-origin suggestions
    /// get an extra "Lifted from" line (TestLifter M3.3) distinct from
    /// the `// Source:` assertion-site pointer.
    ///
    /// The stub is placed inside a suite type named from `fileName` (`namespaced(_:suiteName:)`),
    /// so two stubs whose emitters chose the same test function name do not redeclare it (#467).
    /// Everything the carrier-import resolver needs, bundled into one argument so the writer
    /// stays inside SwiftLint's five-parameter cap.
    ///
    /// `nil` for every caller that has no package to resolve against — the unit fixtures, and
    /// `convert-counterexample` — which then emit exactly the imports they did before.
    public struct CarrierImports: Sendable {
        public let typeShapesByName: [String: TypeShape]
        public let sourceFileByTypeName: [String: String]
        public let packageRoot: URL
        /// Every copied receiver construction with its test file's imports, so a stub that uses one
        /// can import what it names.
        let receiverConstructions: [ReceiverConstructionHarvester.Harvested]

        public init(
            typeShapesByName: [String: TypeShape],
            sourceFileByTypeName: [String: String],
            packageRoot: URL
        ) {
            self.init(
                typeShapesByName: typeShapesByName,
                sourceFileByTypeName: sourceFileByTypeName,
                packageRoot: packageRoot,
                receiverConstructions: []
            )
        }

        init(
            typeShapesByName: [String: TypeShape],
            sourceFileByTypeName: [String: String],
            packageRoot: URL,
            receiverConstructions: [ReceiverConstructionHarvester.Harvested]
        ) {
            self.typeShapesByName = typeShapesByName
            self.sourceFileByTypeName = sourceFileByTypeName
            self.packageRoot = packageRoot
            self.receiverConstructions = receiverConstructions
        }
    }

    static func wrappedFileContents(
        stub: String,
        suggestion: Suggestion,
        moduleUnderTest: String? = nil,
        fileName: String? = nil,
        carrierImports: CarrierImports? = nil,
        sourceModules: SourceModuleResolver? = nil
    ) -> String {
        let location = suggestion.evidence.first?.location
        let sourceLine = location.map { loc in "// Source: \(loc)" } ?? ""
        // Import the module under test so the generated file compiles drop-in.
        // `@testable` reaches internal functions (the common case for the free /
        // internal helpers seeds point at).
        //
        // **Two sources, and the second one is why any of this compiles for an app.** The
        // per-file `Sources/<Module>/` layout answers for a conventional package. It cannot
        // answer for `SwiftMarkdownWiki/Editor/EditorFormatter.swift`, which has no `Sources/`
        // component — and that is the layout `--sources` exists to serve, not a synthetic
        // fixture. The run's manifest-resolved module is consulted next.
        //
        // When neither answers, the file says so on the line that will fail. Emitting nothing
        // was the defect: 0 of 19 stubs named the module under test and nothing reported it, so
        // the failure arrived as an unresolved-symbol error in code the reader did not write
        // (#415).
        // The manifest answers first (`SourceModuleResolver`): the path's `Sources/<Module>/` is a
        // convention a target with its own `path:` breaks — Harbeth's `Sources/Basic/` is target
        // `Harbeth`, and importing `Basic` compiled 0 of 230 stubs.
        let resolvedModule = location.flatMap { loc in
            sourceModules?.module(forSourceFile: loc.file) ?? Self.moduleName(fromSourceFile: loc.file)
        } ?? moduleUnderTest
        let moduleImport = resolvedModule
            .map { "@testable import \($0)\n" }
            ?? "// TODO: no module resolved for this subject — add `@testable import <YourModule>`"
                + " (this file will not compile until you do)\n"
        let liftedLine = suggestion.liftedOrigin.map { origin in
            "// Lifted from \(origin.sourceLocation)"
                + " \(origin.testMethodName)()"
        } ?? ""
        // TestLifter M4.4 — mock-inferred suggestions get a provenance
        // line surfacing construction-site count + .low confidence.
        let mockLine: String = {
            guard suggestion.generator.source == .inferredFromTests,
                  let mock = suggestion.mockGenerator else {
                return ""
            }
            return "// Mock-inferred from \(mock.siteCount) construction"
                + " site\(mock.siteCount == 1 ? "" : "s") in test bodies — low confidence"
                + " (verify the generator covers your domain)"
        }()
        // TestLifter M5.4 — Codable round-trip suggestions get a
        // provenance line surfacing the .medium confidence and the
        // user-action requirement (replacing the placeholder fixture
        // before the generator buys you a real round-trip property).
        let codableLine = Self.codableScaffoldLine(for: suggestion)
        // The access caveat the reader was shown at triage, carried into the file that cannot
        // compile without it.
        //
        // A `private` subject surfaces ON PURPOSE — `SeededPrivateFunctionTests` records the
        // decision and the reasoning: *"purity, shape and role decide whether a law is worth
        // proposing; access level decides what must happen before it can be verified. Access
        // belongs in the advice, never in the gate."* The advice was shown, was correct, and was
        // then dropped at exactly the moment it became actionable — accept wrote a file whose
        // only diagnostic is `'trimmed' is inaccessible due to 'private' protection level`, in
        // code the reader did not write (#428).
        //
        // Read from the `.subjectNotVisibleToTests` signal rather than re-derived, so the remedy
        // has one author: `AccessRestriction.remedy`, the same sentence triage printed.
        let accessLine = Self.accessCaveat(for: suggestion)

        // Foundation, unconditionally. It used to be added only for the Codable round-trip
        // generator scaffold, which needs `JSONEncoder`. That is not the only thing that
        // needs it: a package enabling the `MemberImportVisibility` upcoming feature — this
        // one does — requires every file touching a Foundation member to import it, and a
        // subject like `mimeType` or `bucketURL` reaches Foundation through its own types.
        // An unused import is a no-op; a missing one is a build failure in generated code.
        let foundationImport = "import Foundation\n"
        // A stub drawing from the syntax corpus names SwiftSyntax node types in its closure
        // annotations; imports are per file, so the corpus file's own import does not reach here.
        let syntaxImport = stub.contains("\(SyntaxCorpusSource.typeName).") ? "import SwiftSyntax\n" : ""
        let carrierImportLines = Self.namedTypeImportLines(
            for: suggestion, stub: stub, entryModule: resolvedModule,
            carrierImports: carrierImports, beside: syntaxImport + moduleImport
        )
        let suiteKey = fileName ?? stubFileName(for: suggestion) ?? suggestion.identity.normalized
        let namespacedStub = Self.namespaced(
            stub,
            suiteName: Self.suiteName(forStubFileName: suiteKey)
        )
        return """
        // Auto-generated by `swift-infer discover --interactive` — do not edit.
        \(sourceLine)
        \(liftedLine)
        \(mockLine)
        \(codableLine)
        // Suggestion identity: \(suggestion.identity.display)
        // Template: \(suggestion.templateName)
        \(Self.lawClassLine(for: suggestion, isScaffold: Self.isScaffold(stub)))\(accessLine)
        \(foundationImport)import Testing
        import PropertyBased
        import PropertyLawKit
        \(syntaxImport)\(moduleImport)\(carrierImportLines)\(namespacedStub)
        """
    }

    /// What a **pass** of this test is allowed to mean.
    ///
    /// ## The two are byte-indistinguishable today, and one of them is a guess
    ///
    /// An emitted `idempotence` test and an emitted `input-totality` test differ only in the
    /// template name in the header. One is a law a correct implementation **cannot** fail; the
    /// other is read off a type shape and a verb, and a correct implementation can fail it. A
    /// green tick reports both identically.
    ///
    /// **Measured across two subjects: entailed laws 3 run, 0 false; conjectures 5 run, 3 false**
    /// (`roadtest-swiftmarkdownwiki.md`, `roadtest-swift-argument-parser.md`). The class
    /// predicted every outcome.
    ///
    /// The sharp case is #453. `mimeType_idempotence` was emitted, compiled, ran 100 trials and
    /// **passed**, and the law is false — its counterexamples are the three literals `css`, `js`
    /// and `woff2`, which the generator cannot produce. Nothing in the emitted file, and nothing
    /// in any count the pipeline reports, separates that from the three totality laws that
    /// genuinely passed beside it.
    ///
    /// ## Why the class and not the tier
    ///
    /// Carrying the **tier** was the obvious cheap fix and was measured not to work: `parse` and
    /// `parseQuery` are Possible 30 and true, `mimeType` is Possible 20 and false — the same tier
    /// with opposite verdicts. `Refutability.isRoleEntailed` is the distinction that separated
    /// every outcome, and it already reaches the CLI and gates `isWorthSurfacingBelowCut`. It
    /// simply never reached the test target.
    ///
    /// ## What this does not do
    ///
    /// It does not make a conjecture true, catch a false pass, or change which laws are emitted.
    /// It tells the reader which kind of claim a green tick is, which is the whole of the fix —
    /// #453's other two directions were measured and declined on population.
    ///
    /// ## Three classes, not two (#466)
    ///
    /// This was a two-way switch — entailed, else conjecture — so `determinism`, the one member of
    /// `Refutability.tautologicalTemplates`, was labelled the class it is least like: a
    /// CONJECTURE, "a CORRECT implementation can fail it", on `f(x) == f(x)`. The terminal
    /// renderer never made that mistake (`SuggestionRenderer` gates its conjecture caveat on
    /// `isRefutable && !isRoleEntailed`), so only the file a reader keeps said it.
    ///
    /// A passing determinism test is the weakest green in the target, and its failure is the
    /// informative outcome: both measured in the corpus funnel census were genuine hidden state —
    /// a process-wide counter bumped per call. **The line does not claim a failure proves
    /// impurity**, because it does not: the emitter compares strictly unless the return type is
    /// itself floating-point, so a pure function returning `[Double]` that holds a NaN fails
    /// (`[Double.nan] == [Double.nan]` is false), as does a result whose `==` compares identity.
    /// **A tuple result is compared strictly too**, element by element through the standard
    /// library's tuple `==` — `(Double, Double)` is not a floating-point type name, and the
    /// approximate helper is generic over `FloatingPoint`, which no tuple is — so a NaN in any
    /// slot fails it the same way. The line says "or tuple" for a tuple result only, so every
    /// other file's header is unchanged.
    ///
    /// ## A scaffold is not a law at all (#466)
    ///
    /// A `replay-idempotence` stub cannot build its own fixture, so it records an issue on
    /// purpose, naming the steps left to complete, and fails until a person completes them. It
    /// used to carry the CONJECTURE line — *"a pass means no counterexample was found"* — on a
    /// file that can never pass as written.
    /// Checked first and read from the stub rather than from the template name, so the line
    /// follows what the file does: `isScaffold(_:)`.
    static func lawClassLine(for suggestion: Suggestion, isScaffold: Bool = false) -> String {
        if isScaffold {
            return """
            // Law class: SCAFFOLD — not a law yet. It records an issue on purpose until you
            //            complete the steps it lists, so it fails by design: red here is work
            //            left to do, not a verdict about the code.

            """
        }
        if Refutability.isRefutable(suggestion) == false {
            let resultShape = TupleResultShape(signature: suggestion.evidence.first?.signature ?? "")
            let container = resultShape.involvesTuple ? "collection or tuple" : "collection"
            return """
            // Law class: TAUTOLOGY — true of any pure implementation, so a pass only means no hidden
            //            state showed up in the trials drawn. A failure means either the subject
            //            is not pure, or its result's `==` is not reflexive (a NaN inside a
            //            \(container), an identity comparison).

            """
        }
        // Checked BEFORE `isRoleEntailed`, which it is a subset of. A characterisation law is
        // entailed — and saying only that would tell the reader a pass is "a statement about the
        // code", when the code satisfies the law by construction and a pass says nothing about
        // today's behaviour. Same failure the TAUTOLOGY line exists to prevent (#466).
        if Refutability.isCharacterisation(suggestion) {
            return characterisationHeader(templateName: suggestion.templateName)
        }
        if Refutability.isRoleEntailed(suggestion) {
            return """
            // Law class: ENTAILED — a correct implementation cannot fail this, so a pass is a
            //            statement about the code.

            """
        }
        return """
        // Law class: CONJECTURE — read from the signature and the name, not entailed by either,
        //            so a CORRECT implementation can fail it. A pass means no counterexample was
        //            found in the trials drawn, NOT that the law holds: a law whose
        //            counterexamples lie outside the generator's reach passes while being false.

        """
    }

    /// Whether a stub body is a scaffold: a test that records an issue on purpose, its message
    /// opening with the to-do marker, until a person completes it.
    ///
    /// Read from the body rather than from the template name because the property belongs to the
    /// file, not the template — today four emitters write one (`LiftedTestEmitter.replayIdempotent`,
    /// `replayKeyBuilder`, `stateMachineScaffold`, `structuralRoundTripScaffold`), and a template
    /// that starts writing one tomorrow is labelled correctly without anyone remembering this
    /// function. `Refutability.scaffoldTemplates` is a different, narrower question: which
    /// suggestions owe no conjecture caveat in `discover`'s output, before any stub exists.
    static func isScaffold(_ stub: String) -> Bool {
        stub.contains("Issue.record(\"TODO")
    }

    /// The module under test, derived from a source file path laid out the SPM
    /// way (`.../Sources/<Module>/<File>.swift`). Returns `nil` for paths with no
    /// `Sources/` component (e.g. unit-test fixtures), so the `@testable import`
    /// is added only when it can be inferred — keeping generated tests drop-in
    /// compilable for real packages without guessing for synthetic ones.
    static func moduleName(fromSourceFile path: String) -> String? {
        let components = path.split(separator: "/").map(String.init)
        guard let sourcesIndex = components.lastIndex(of: "Sources"),
              sourcesIndex + 1 < components.count else {
            return nil
        }
        let candidate = components[sourcesIndex + 1]
        return candidate.hasSuffix(".swift") ? nil : moduleIdentifier(from: candidate)
    }

    /// The Swift module name SwiftPM synthesizes for a target directory. SwiftPM
    /// replaces every character that isn't valid in a Swift identifier with `_`,
    /// so the directory `swift-clone-detector` is imported as
    /// `swift_clone_detector`. Emitting the raw directory name produced
    /// `@testable import swift-clone-detector`, which is a syntax error and broke
    /// every generated stub for a hyphen- or dot-named target.
    static func moduleIdentifier(from targetDirectory: String) -> String {
        let allowed: Set<Character> = Set(
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
        )
        return String(targetDirectory.map { allowed.contains($0) ? $0 : "_" })
    }
}
