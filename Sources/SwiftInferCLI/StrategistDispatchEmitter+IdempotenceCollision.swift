import SwiftInferCore

/// Split from `StrategistDispatchEmitter+Templates.swift` for `file_length`.
extension StrategistDispatchEmitter {

    static func idempotenceCollisionBody(dedupeBody: DedupeBody? = nil) -> String {
        """
                let collisionOnce = applyOnce(collisionValue)
                let collisionTwice = applyOnce(collisionOnce)
                if \(dedupeMismatch(once: "collisionOnce", twice: "collisionTwice", body: dedupeBody)) {
                    print("VERIFY_DEFAULT_RESULT: FAIL")
                    print("VERIFY_DEFAULT_PASS_KIND: collision")
                    print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                    print("VERIFY_DEFAULT_INPUT: \\(collisionValue)")
                    print("VERIFY_DEFAULT_FORWARD: \\(collisionTwice)")
                    print("VERIFY_DEFAULT_INVERSE: \\(collisionOnce)")
                    exit(1)
                }
        """
    }

    /// The idempotence oracle's failure condition: `once != twice`, or, for a dictionary-route
    /// dedupe (#711), the same without order: a count that differs, or an element of `twice` not
    /// in `once`.
    ///
    /// **Why.** A dictionary-route body returns `Array(d.values)`, so the second call lists the
    /// same values in another dictionary's hash order. #734's review measured the strict law
    /// failing a correct `byKey[word.lowercased()] = word` dedupe in 4 of 4 runs, at an input with
    /// no duplicates. The accepted stub states it the same way
    /// (`LiftedTestEmitter.idempotentIgnoringOrder`), so a stub and a verify run cannot disagree.
    static func dedupeMismatch(once: String, twice: String, body: DedupeBody?) -> String {
        guard let body, !body.keepsFirst else { return "\(once) != \(twice)" }
        return "\(twice).count != \(once).count || !\(twice).allSatisfy { element in \(once).contains(element) }"
    }
}
