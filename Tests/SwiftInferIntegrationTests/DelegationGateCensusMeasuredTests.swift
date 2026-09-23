import Foundation
import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
@testable import SwiftInferTemplates
import SwiftParser
import SwiftSyntax
import Testing

/// **What would resolving a delegating initializer to its actual target recover?** —
/// `open-threads.md` row 72, `docs/measurements/delegation-gate-census.md`.
///
/// The kit declines a delegating initializer when *any* initializer on its type asserts
/// (`InitializerBasedDerivation.isDeclined`), because matching `self.init(…)` to one overload
/// would mean overload resolution. On Euclid that withdrew `Path` and `LineSegment` with `Plane`,
/// though only `Plane`'s target asserts. This asks how often that happens on the manifest.
///
/// **Nothing about the gate is restated.** The real `GeneratorResolver` runs twice over the same
/// scan: once on the shapes as built, once on shapes where a delegating initializer's
/// `delegatesToSelf` is cleared when its target is resolved — by argument labels, following
/// chains — and asserts nothing. A type counts as GAINED when the first has no generator and the
/// second has one. Anything unresolved or ambiguous stays gated, so the counterfactual is itself
/// conservative.
///
/// ⚠ The kit's `delegatesToSelf` fires on ANY `.init` member access, so `values = .init(…)` or
/// `Foo.init(x)` inside a body reads as delegation. Such an initializer has no `self.init` call
/// at all; it is reported as its own bucket and cleared in the counterfactual.
///
///     SWIFT_INFER_DELEGATION_CENSUS=/path/to/scan/dir swift test --filter DelegationGateCensus
@Suite(
    "Delegation gate — what a precise target would recover",
    .tags(.subprocess),
    .enabled(
        if: ProcessInfo.processInfo.environment["SWIFT_INFER_DELEGATION_CENSUS"] != nil,
        "opt-in census; set SWIFT_INFER_DELEGATION_CENSUS=<scan directory>"
    )
)
struct DelegationGateCensusMeasuredTests {

    @Test("the gate as shipped against a gate that resolves the target")
    func compareShippedAndPreciseGates() throws {
        let root = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SWIFT_INFER_DELEGATION_CENSUS"]!
        )
        let artifacts = try TemplateRegistry.discoverArtifacts(in: root)
        let shapes = TypeShapeBuilder.shapes(from: artifacts.typeDecls)
        let syntax = try Self.initializerSyntax(under: root)

        var tally = Tally()
        let counterfactual = shapes.map { Self.rebuild($0, inits: syntax[$0.name] ?? [], tally: &tally) }
        let shipped = GeneratorResolver(types: shapes)
        let precise = GeneratorResolver(types: counterfactual)
        let gained = shapes.filter { $0.kind == .struct }.map(\.name).filter {
            shipped.customTypeGenerator(forTypeName: $0) == nil
                && precise.customTypeGenerator(forTypeName: $0) != nil
        }
        let lost = shapes.map(\.name).filter {
            shipped.customTypeGenerator(forTypeName: $0) != nil
                && precise.customTypeGenerator(forTypeName: $0) == nil
        }

        print("DELEGATION-CENSUS|\(root.path)|shapes=\(shapes.count)|fires=\(tally.fires.count)"
            + "|wrong=\(tally.wrong.count)|notDelegation=\(tally.notDelegation.count)"
            + "|unresolvedInits=\(tally.unresolved)|gained=\(gained.count)|lost=\(lost.count)")
        Self.reportTypes(tally: tally, gained: gained, shipped: shipped)
        // The instrument, not the answer: the counterfactual only ever removes a decline, so a
        // type that LOSES a generator means the rebuild dropped something.
        #expect(lost.isEmpty, "the counterfactual lost generators: \(lost)")
        #expect(!shapes.isEmpty, "the scan resolved no type shapes at all")
    }

    /// What the census counts, per scan: types the gate fires on, the subset where a declined
    /// initializer's target is clean, the subset of those that never delegate at all, and how
    /// many delegating initializers the label match could not resolve.
    struct Tally {
        var fires: [String] = []
        var wrong: Set<String> = []
        var notDelegation: Set<String> = []
        var unresolved = 0
    }

    /// `shape` as a precise gate would see it: every delegating initializer whose target is clean
    /// (or which never really delegates) has `delegatesToSelf` cleared. Types the gate does not
    /// fire on come back unchanged.
    static func rebuild(_ shape: TypeShape, inits: [InitSyntax], tally: inout Tally) -> TypeShape {
        let gated = shape.kind == .struct
            && shape.initializers.contains(where: \.assertsPrecondition)
            && shape.initializers.contains(where: \.delegatesToSelf)
        guard gated else { return shape }
        tally.fires.append(shape.name)
        let rebuilt = shape.initializers.map { signature -> InitializerSignature in
            guard signature.delegatesToSelf, !signature.assertsPrecondition else { return signature }
            let verdict = verdict(for: signature, among: inits, shape: shape)
            let labels = signature.parameters.map { $0.label ?? "_" }.joined(separator: ":")
            switch verdict {
            case .clean, .notADelegation:
                print("DELEGATION-CLEARED|\(shape.name)|init(\(labels))|\(verdict)")
                tally.wrong.insert(shape.name)
                if verdict == .notADelegation { tally.notDelegation.insert(shape.name) }
                return clearingDelegation(signature)

            case .asserts:
                return signature

            case .unresolved(let why):
                tally.unresolved += 1
                print("DELEGATION-UNRESOLVED|\(shape.name)|init(\(labels))|\(why)")
                return signature
            }
        }
        return Self.shape(shape, initializers: rebuilt)
    }

    /// One line per type the gate fires on, plus the types that gained a generator only because a
    /// type they are built from did.
    static func reportTypes(tally: Tally, gained: [String], shipped: GeneratorResolver) {
        for name in gained.sorted() where !tally.fires.contains(name) {
            print("DELEGATION-TYPE|\(name)|GAINED-DOWNSTREAM")
        }
        for name in tally.fires.sorted() {
            var tags: [String] = []
            if tally.wrong.contains(name) { tags.append("WRONG") }
            if tally.notDelegation.contains(name) { tags.append("NOT-DELEGATION") }
            if gained.contains(name) { tags.append("GAINED") }
            if shipped.customTypeGenerator(forTypeName: name) != nil { tags.append("HAS-GENERATOR") }
            print("DELEGATION-TYPE|\(name)|\(tags.joined(separator: ","))")
        }
    }

    // MARK: - Target resolution

    enum Verdict: Equatable { case clean, asserts, unresolved(String), notADelegation }

    struct InitSyntax {
        let labels: [String?]
        let defaulted: [Bool]
        /// Argument labels of each `self.init(…)` / `Self.init(…)` call in the body.
        let delegations: [[String?]]
    }

    /// The verdict for one delegating initializer: find its syntax by parameter labels, then
    /// follow every `self.init` call it makes until each ends at an initializer that neither
    /// asserts nor delegates. Anything ambiguous is `.unresolved`, which keeps the gate.
    ///
    /// Whether a target asserts is read off the SHAPE — the kit's own
    /// `InitializerPreconditionDetector` computed it — matched by parameter labels, so this
    /// census never restates what counts as a precondition.
    static func verdict(
        for signature: InitializerSignature,
        among inits: [InitSyntax],
        shape: TypeShape
    ) -> Verdict {
        let labels = signature.parameters.map(\.label)
        let own = inits.filter { $0.labels == labels }
        guard own.count == 1, let start = own.first else { return .unresolved("own syntax matches \(own.count)") }
        if start.delegations.isEmpty { return .notADelegation }
        var seen: [[String?]] = []
        var pending = start.delegations
        while let call = pending.popLast() {
            let targets = inits.filter { accepts($0, call) }
            guard targets.count == 1, let target = targets.first else {
                return .unresolved("call \(call.map { $0 ?? "_" }) matches \(targets.count) initializers")
            }
            let flagged = shape.initializers.filter { $0.parameters.map(\.label) == target.labels }
            guard flagged.count == 1 else { return .unresolved("target has \(flagged.count) shape signatures") }
            if flagged[0].assertsPrecondition { return .asserts }
            if seen.contains(target.labels) { continue }
            seen.append(target.labels)
            pending += target.delegations
        }
        return .clean
    }

    /// Whether `target` accepts a call with these argument labels, allowing defaulted
    /// parameters to be omitted in order.
    static func accepts(_ target: InitSyntax, _ call: [String?]) -> Bool {
        var index = 0
        for (label, hasDefault) in zip(target.labels, target.defaulted) {
            if index < call.count, call[index] == label {
                index += 1
            } else if !hasDefault {
                return false
            }
        }
        return index == call.count
    }

    /// Every initializer under `root`, keyed by the dot-qualified name of the type that declares
    /// or extends it — the same key `TypeShapeBuilder` names a shape by.
    static func initializerSyntax(under root: URL) throws -> [String: [InitSyntax]] {
        var result: [String: [InitSyntax]] = [:]
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            let path = url.path
            guard path.hasSuffix(".swift"),
                  !path.contains("/.build/"), !path.contains("/Tests/"),
                  !path.contains("/.swiftinfer/") else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            let collector = InitCollector(viewMode: .sourceAccurate)
            collector.walk(Parser.parse(source: source))
            result.merge(collector.found) { $0 + $1 }
        }
        return result
    }

    final class InitCollector: SyntaxVisitor {
        var found: [String: [InitSyntax]] = [:]
        private var stack: [String] = []

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            stack.append(node.name.text); return .visitChildren
        }
        override func visitPost(_: StructDeclSyntax) { stack.removeLast() }
        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            stack.append(node.name.text); return .visitChildren
        }
        override func visitPost(_: ClassDeclSyntax) { stack.removeLast() }
        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            stack.append(node.name.text); return .visitChildren
        }
        override func visitPost(_: EnumDeclSyntax) { stack.removeLast() }
        override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
            stack.append(node.name.text); return .visitChildren
        }
        override func visitPost(_: ActorDeclSyntax) { stack.removeLast() }
        override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
            let extended = node.extendedType.trimmedDescription
            stack.append(extended.replacingOccurrences(of: #"<.*>"#, with: "", options: .regularExpression))
            return .visitChildren
        }
        override func visitPost(_: ExtensionDeclSyntax) { stack.removeLast() }

        override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
            guard !stack.isEmpty else { return .skipChildren }
            let parameters = node.signature.parameterClause.parameters
            let labels = parameters.map { $0.firstName.text == "_" ? nil : $0.firstName.text }
            let delegations = node.body.map { SelfInitCalls.labels(in: Syntax($0)) } ?? []
            found[stack.joined(separator: "."), default: []].append(InitSyntax(
                labels: labels,
                defaulted: parameters.map { $0.defaultValue != nil },
                delegations: delegations
            ))
            return .skipChildren
        }
    }

    /// The argument labels of every `self.init(…)` / `Self.init(…)` call beneath `node` — the
    /// calls that really are delegation, unlike a bare `.init(…)` or `Other.init(…)`.
    enum SelfInitCalls {
        static func labels(in node: Syntax) -> [[String?]] {
            var result: [[String?]] = []
            if let call = node.as(FunctionCallExprSyntax.self),
               let member = call.calledExpression.as(MemberAccessExprSyntax.self),
               member.declName.baseName.text == "init",
               let base = member.base?.trimmedDescription, base == "self" || base == "Self" {
                result.append(call.arguments.map { $0.label?.text })
            }
            for child in node.children(viewMode: .sourceAccurate) {
                result += labels(in: child)
            }
            return result
        }
    }

    // MARK: - Rebuilding shapes

    static func clearingDelegation(_ signature: InitializerSignature) -> InitializerSignature {
        InitializerSignature(
            parameters: signature.parameters,
            isFailable: signature.isFailable,
            isThrowing: signature.isThrowing,
            assertsPrecondition: signature.assertsPrecondition,
            delegatesToSelf: false,
            accessLevel: signature.accessLevel
        )
    }

    static func shape(_ shape: TypeShape, initializers: [InitializerSignature]) -> TypeShape {
        TypeShape(
            name: shape.name,
            kind: shape.kind,
            inheritedTypes: shape.inheritedTypes,
            hasUserGen: shape.hasUserGen,
            storedMembers: shape.storedMembers,
            hasUserInit: shape.hasUserInit,
            initializers: initializers,
            enumCases: shape.enumCases,
            accessLevel: shape.accessLevel,
            hasPrimaryDeclaration: shape.hasPrimaryDeclaration
        )
    }
}
