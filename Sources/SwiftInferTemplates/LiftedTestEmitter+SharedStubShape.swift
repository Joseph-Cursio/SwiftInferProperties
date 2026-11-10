import PropertyLawCore
import SwiftInferCore

// V1.43 cleanup — private builders live here so the primary
// enum body stays under SwiftLint's type_body_length cap.
extension LiftedTestEmitter {

    // MARK: - Shared stub shape

    /// Convenience overload for unary-property arms — wraps the canonical
    /// `{ rng in (generator).run(using: &rng) }` sample and a single-value
    /// property closure, then forwards to `makeTestStubExpression`.
    /// Shared scaffold for every arm — they differ only in the sample /
    /// property closure shape and failure-label string. Module-private
    /// (not file-private) so the M5.5 lifted-only arms in
    /// `LiftedTestEmitter+M5.swift` can reuse it.
    static func makeTestStubExpression(
        testFunctionName: String,
        seed: SamplingSeed.Value,
        sampleExpression: String,
        propertyExpression: String,
        failureLabel: String
    ) -> String {
        """

        @Test func \(testFunctionName)() async {
            let backend = SwiftPropertyBasedBackend()
            let seed = Seed(
                stateA: 0x\(hex(seed.stateA)),
                stateB: 0x\(hex(seed.stateB)),
                stateC: 0x\(hex(seed.stateC)),
                stateD: 0x\(hex(seed.stateD))
            )
            let result = await backend.check(
                trials: 100,
                seed: seed,
                sample: \(sampleExpression),
                property: \(propertyExpression)
            )
            if case let .failed(_, _, input, error) = result {
                Issue.record(
                    "\(escapedForLiteral(failureLabel)) at input \\(input). \\(error?.message ?? "")"
                )
            }
        }
        """
    }

    /// `\.isValid` → `isValid`; `\.account.balance` → `account_balance`.
    /// Used only for test-function-name suffixes; the keypath itself is
    /// emitted verbatim into the property closure.
    static func sanitizeKeyPathForIdentifier(_ keyPath: String) -> String {
        var sanitized = keyPath
        if sanitized.hasPrefix("\\.") {
            sanitized = String(sanitized.dropFirst(2))
        }
        return sanitized.replacingOccurrences(of: ".", with: "_")
    }

    static func hex(_ word: UInt64) -> String {
        let raw = String(word, radix: 16, uppercase: true)
        return String(repeating: "0", count: 16 - raw.count) + raw
    }
}
