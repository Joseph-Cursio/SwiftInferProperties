import SwiftInferCore
import SwiftInferTemplates

extension InteractiveTriage {

    /// The `uniquifier` stub (#692): the state built once per trial and the subject called once per drawn
    /// name, so the receiver is bound with `let` (or `var`) rather than constructed at every call, which is
    /// what `HeldReceiver` does for `determinism` and would make this law vacuous.
    ///
    /// The receiver's construction is its reserving initializer over the drawn names when it has one
    /// (`UniquifierReservation`), else the one the package's own tests write, or `TrivialConstruction`
    /// (`receiverExpression`). When the name does not enter through one `String` parameter, each argument is
    /// left as a placeholder naming `name`, and the stub does not compile until a reader builds it. A subject
    /// isolated to a global actor gets no stub for now: the check runs in a `@Sendable` closure off the actor.
    static func uniquifierStub(
        for suggestion: Suggestion,
        receiverExpression: ((String) -> String?)?
    ) -> String? {
        guard let match = suggestion.match?.uniquifierMatch, let evidence = suggestion.evidence.first,
              let callee = match.form == .mutating
                  ? CalleeReference.mutatingStatement(evidence: evidence)
                  : CalleeReference(evidence: evidence),
              callee.isolation == nil else {
            return nil
        }
        let arguments = match.parameterTypes.indices.map { index in
            if case .inoutParameter(let state, _) = match.form, state == index { return "&state" }
            return index == match.nameParameter ? "name" : "<#\(match.parameterTypes[index]) built from `name`#>"
        }
        let binding: String
        let call: String
        switch match.form {
        case .instance, .mutating:
            let type = evidence.qualifiedTypeName ?? suggestion.carrier ?? "Subject"
            let construction = match.reservation.map { reserving(type, $0) }
                ?? receiverExpression?(type) ?? "<#construct a \(type)#>"
            binding = "\(match.form == .mutating ? "var" : "let") subject = \(construction)"
            call = callee.call(["subject"] + arguments)

        case .inoutParameter(_, let collectionType):
            let isDictionary = collectionType.hasPrefix("Dictionary") || collectionType.hasPrefix("OrderedDictionary")
                || (collectionType.hasPrefix("[") && collectionType.contains(":"))
            binding = "var state: \(collectionType) = \(isDictionary ? "[:]" : "[]")"
            call = callee.call(arguments)
        }
        let stub = LiftedTestEmitter.UniquifierStub(
            identifierName: callee.identifierName,
            displaySignature: callee.displaySignature,
            binding: binding,
            call: call,
            match: match
        )
        return LiftedTestEmitter.uniquifierLaw(stub, seed: SamplingSeed.derive(from: suggestion.identity))
    }

    /// `type` built through its reserving initializer from the drawn names, the domain its contract owes
    /// distinct results over: `NodeIdAllocator(reserving: names)`.
    private static func reserving(_ type: String, _ reservation: UniquifierReservation) -> String {
        let arguments = zip(reservation.labels, reservation.types).map { label, parameterType in
            let value = parameterType.filter { !$0.isWhitespace }.hasPrefix("Set") ? "Set(names)" : "names"
            return label.map { "\($0): \(value)" } ?? value
        }
        return "\(type)(\(arguments.joined(separator: ", ")))"
    }
}
