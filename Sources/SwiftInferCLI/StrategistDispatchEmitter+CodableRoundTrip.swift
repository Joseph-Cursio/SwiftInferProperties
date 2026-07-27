import Foundation
import SwiftInferCore

// Split from `StrategistDispatchEmitter+Templates.swift` to keep that file under
// the `file_length` cap after the unary collision sweep was wired in. Holds the
// codable-round-trip pass, which is self-contained: it is the one template whose
// oracle is a codec rather than a call to the function under test.
extension StrategistDispatchEmitter {

    /// The collision sweep's per-trial body for the codable round trip, hoisted
    /// out of the composer so that function stays under the body-length cap.
    private static func codableCollisionBody(carrier: String) -> String {
        """
                do {
                    let encoded = try roundTripEncoder.encode(collisionValue)
                    let decoded = try roundTripDecoder.decode(\(carrier).self, from: encoded)
                    if decoded != collisionValue {
                        print("VERIFY_DEFAULT_RESULT: FAIL")
                        print("VERIFY_DEFAULT_PASS_KIND: collision")
                        print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                        print("VERIFY_DEFAULT_INPUT: \\(collisionValue)")
                        print("VERIFY_DEFAULT_DECODED: \\(decoded)")
                        exit(1)
                    }
                } catch {
                    print("VERIFY_DEFAULT_RESULT: FAIL")
                    print("VERIFY_DEFAULT_PASS_KIND: collision")
                    print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                    print("VERIFY_DEFAULT_INPUT: \\(collisionValue)")
                    print("VERIFY_DEFAULT_DETAIL: codec threw: \\(error)")
                    exit(1)
                }
        """
    }

    static func composeCodableRoundTripPass(
        recipe: GeneratorRecipe
    ) -> String {
        let carrier = recipe.carrierTypeName
        return """
        // --- Pass 1: default (strategist-derived generator) ---

        let defaultGenerator: Generator<\(carrier), some SendableSequenceType> =
            \(recipe.expression)
        let roundTripEncoder = JSONEncoder()
        let roundTripDecoder = JSONDecoder()

        for trial in 0 ..< trials {
            let value = defaultGenerator.run(using: &rng)
            do {
                let encoded = try roundTripEncoder.encode(value)
                let decoded = try roundTripDecoder.decode(\(carrier).self, from: encoded)
                if decoded != value {
                    print("VERIFY_DEFAULT_RESULT: FAIL")
                    print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                    print("VERIFY_DEFAULT_INPUT: \\(value)")
                    print("VERIFY_DEFAULT_DECODED: \\(decoded)")
                    exit(1)
                }
            } catch {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: \\(value)")
                print("VERIFY_DEFAULT_DETAIL: codec threw: \\(error)")
                exit(1)
            }
        }


        \(CollisionPass.unarySweep(carrier: carrier, body: codableCollisionBody(carrier: carrier)))
        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    // MARK: - Idempotence (1 value per trial; f(f(x)) == f(x))
}
