import Foundation
import PropertyLawCore
import SwiftInferCore
import SwiftInferTemplates

/// The accept-path arm for `guard-domain` — #468's largest writerless population, 62 declined
/// suggestions across 14 repositories.
///
/// Its own file because its job is unlike every other arm's. The others compose a law out of the
/// tool's own vocabulary; this one takes **source text the tool did not write** — the condition and
/// the returned expression, exactly as the author spelled them inside the declaration — and rebinds
/// every free name to something a test can evaluate. `GuardDomainRebinding` owns that rewrite and
/// its three corruption modes; this file owns which names get bound to what, and when to decline.
///
/// **Rebind or decline, never partially.** Measured over the 20 manifest corpora: 129 of 156
/// statable sites have every free name binding to a parameter, `self`, `Self` or a literal, and the
/// 27 that do not are underscored internals (`_fastPath`, `_root`, `_count`). Emitting for those 27
/// would produce files that do not compile for a reason the reader would have to work out — the
/// 145-of-163 failure `criterion-a-unmet-subject.md` recorded.
extension InteractiveTriage {

    /// A guard-domain characterisation stub, or `nil` when the law cannot be rebound.
    static func guardDomainStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)?
    ) -> String? {
        guard let evidence = suggestion.evidence.first,
              let callee = CalleeReference(evidence: evidence),
              let domain = suggestion.match?.guardDomainMatch,
              let argumentTypes = arityFreeArgumentTypes(callee: callee, evidence: evidence),
              let bindings = guardDomainBindings(
                  callee: callee, evidence: evidence, parameterCount: argumentTypes.count
              ),
              let condition = GuardDomainRebinding.rebind(domain.condition, bindings: bindings),
              let returned = GuardDomainRebinding.rebind(domain.returnedExpression, bindings: bindings)
        else {
            return nil
        }
        // A `guard` fires its early return when the condition FAILS; an `if` when it holds. The
        // template's own signal renders the same negation, and getting it backwards states the
        // law over the complement of the sub-domain it was read from.
        let predicate = domain.firesWhenConditionHolds ? "(\(condition))" : "!(\(condition))"
        return LiftedTestEmitter.guardDomain(
            LiftedTestEmitter.GuardDomainCall(
                callee: callee,
                generators: argumentTypes.map {
                    chooseGenerator(for: suggestion, typeName: $0, customGenerator: customGenerator)
                },
                domainPredicate: predicate,
                returnedExpression: returned,
                statedLaw: statedLaw(domain: domain, callee: callee)
            ),
            seed: SamplingSeed.derive(from: suggestion.identity)
        )
    }

    /// Why a guard-domain law cannot be written, or `nil` when it can.
    ///
    /// **Names the free identifier that defeated it.** A decline a reader cannot act on is the
    /// failure `StubApplicationArity` exists to prevent one layer up — *"no stub writeout
    /// available"* told 62 readers nothing about their own code.
    static func guardDomainDeclineReason(for suggestion: Suggestion) -> String? {
        guard let evidence = suggestion.evidence.first,
              let callee = CalleeReference(evidence: evidence),
              let domain = suggestion.match?.guardDomainMatch else {
            return nil
        }
        guard let argumentTypes = arityFreeArgumentTypes(callee: callee, evidence: evidence),
              let bindings = guardDomainBindings(
                  callee: callee, evidence: evidence, parameterCount: argumentTypes.count
              ) else {
            return "\(callee.displaySignature) cannot be called from a test, so its guard cannot be stated"
        }
        let unbound = GuardDomainRebinding.unboundNames(
            in: domain.condition + " " + domain.returnedExpression, bindings: bindings
        )
        guard !unbound.isEmpty else { return nil }
        return "the guard names \(unbound.map { "`\($0)`" }.joined(separator: ", ")), which a test "
            + "cannot bind — the law is stated over the declaration's own scope, and these are not "
            + "parameters, the receiver, or its type"
    }

    /// What each free name in the condition rebinds to.
    ///
    /// - **Every parameter**, by *internal* name — the name the body uses, not the label a caller
    ///   writes. `func wordCount(forScale scale: Int)` has a condition over `scale`.
    /// - **`self`** → the drawn receiver, which for an instance method is the first argument the
    ///   stub supplies. Absent for a static or free function, where a condition mentioning `self`
    ///   declines rather than binding to nothing.
    /// - **`Self`** → the declaring type, qualified as a test must spell it.
    ///
    /// `nil` when the recorded parameter list does not match the call's arity, which would mean
    /// binding names positionally against a signature that disagrees.
    private static func guardDomainBindings(
        callee: CalleeReference,
        evidence: Evidence,
        parameterCount: Int
    ) -> [String: String]? {
        let names = evidence.parameterInternalNames
        let receiverOffset = callee.isInstanceMethod ? 1 : 0
        guard names.count == parameterCount - receiverOffset else { return nil }
        var bindings: [String: String] = [:]
        for (index, name) in names.enumerated() where !name.isEmpty {
            bindings[name] = "arg\(index + receiverOffset)"
        }
        if callee.isInstanceMethod { bindings["self"] = "arg0" }
        if let declaringType = evidence.qualifiedTypeName { bindings["Self"] = declaringType }
        for typeName in typeNamesInSignature(evidence.signature) { bindings[typeName] = typeName }
        return bindings
    }

    /// Type names appearing in the subject's own signature, each bound **to itself**.
    ///
    /// **A test that can call the function can already name every type in its signature** — that is
    /// what makes this sound rather than optimistic. `parse(from: String) -> (FrontMatter, String)`
    /// returns `(FrontMatter(), source)` from its guard, spelling the concrete type rather than
    /// `Self`, and that is the template's own documented example: declining it would decline the
    /// case the template was built for.
    ///
    /// ⚠ **Scoped to the signature deliberately, and the alternatives are worse.** Binding every
    /// capitalised name would admit `StmtSyntax`, `NSData` and `_AttributeStorage` — types from
    /// modules the stub does not import, or nested types spelled unqualified inside their own
    /// declaration, both of which emit a file that does not compile. Consulting the scanned type
    /// universe instead would be sound too and needs the universe threaded through four emitter
    /// signatures; the signature is already here and answers the motivating case.
    private static func typeNamesInSignature(_ signature: String) -> [String] {
        var names: [String] = []
        var current = ""
        for character in signature {
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
                continue
            }
            if let first = current.first, first.isUppercase, !names.contains(current) {
                names.append(current)
            }
            current = ""
        }
        if let first = current.first, first.isUppercase, !names.contains(current) { names.append(current) }
        return names
    }

    /// The law as one sentence — the reader's own line played back, which
    /// `GuardDomainTemplate`'s caveat says is the whole product of this template.
    private static func statedLaw(domain: GuardDomain, callee: CalleeReference) -> String {
        let arrow = domain.firesWhenConditionHolds ? "" : "!"
        return "\(arrow)(\(domain.condition)) ⟹ \(callee.displaySignature) == \(domain.returnedExpression)"
    }
}
