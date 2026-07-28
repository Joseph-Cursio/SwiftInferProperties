import Foundation

/// Split from `StrategistDispatchEmitter+Templates.swift` for `file_length`.
extension StrategistDispatchEmitter {

    static func idempotenceCollisionBody() -> String {
        """
                let collisionOnce = applyOnce(collisionValue)
                let collisionTwice = applyOnce(collisionOnce)
                if collisionTwice != collisionOnce {
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
}
