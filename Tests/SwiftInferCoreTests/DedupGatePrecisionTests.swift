@testable import SwiftInferCore
import Testing

/// Reads the `dedupGateShape` off a body parsed via the scanner (shared with
/// `DedupGateClassifierTests`).
private func gate(_ source: String) throws -> DedupGateShape? {
    let summaries = FunctionScanner.scanCorpus(source: source, file: "S.swift").summaries
    return try #require(summaries.first).bodySignals.dedupGateShape
}

/// The precision refinements and vetoes — the "NOT a gate" half, split out to keep
/// each suite under the type-body length cap.
@Suite("DedupGateClassifier — precision refinements & vetoes")
struct DedupGatePrecisionTests {

    @Test("Reject-on-duplicate by throwing is NOT a gate (MacCloud uploadFile)")
    func rejectOnDuplicateByThrowingIsNotAGate() throws {
        // MacCloud_server uploadFile: `if fileExists { throw }` — the branch
        // throws rather than returns, so the handler is NOT idempotent, and the
        // gate must not fire. blockReturns is false → skipped.
        let shape = try gate("""
        struct H {
            func upload(req: Request) async throws -> Row {
                let fileExists = try await File.query(on: req.db).first() != nil
                if fileExists { throw FileError.fileAlreadyExists }
                return Row()
            }
        }
        """)
        #expect(shape == nil)
    }

    @Test("Guard-form claim-once dedup is detected (penny canGiveCoin, M5)")
    func guardClaimOnceDetected() throws {
        // penny-bot ReactionHandler.handle: `guard await cache.canGiveCoin(…) else
        // { return }` before awarding — the guard-form dedup M4's sweep found missed.
        let shape = try gate("""
        struct H {
            func handle() async throws {
                guard let member = event.member,
                      await cache.canGiveCoin(sender: member.id, message: messageId)
                else { return }
                try await coinService.post(to: member.id)
            }
        }
        """)
        #expect(shape == .guardDedup(verb: "canGiveCoin"))
    }

    @Test("Guard on a negated dedup check is detected (M5)")
    func guardNegatedDedupDetected() throws {
        let shape = try gate("""
        struct H {
            func handle(_ key: Key) async throws {
                guard !dedup.hasHandled(key) else { return }
                try await repo.insert(key)
            }
        }
        """)
        #expect(shape == .guardDedup(verb: "hasHandled"))
    }

    @Test("A permission guard that throws is NOT a gate (precision, M5)")
    func permissionGuardThatThrowsIsNotAGate() throws {
        // `guard file.canWrite(user) else { throw }` — authorisation, not dedup:
        // the verb is a permission verb AND the else throws rather than returns.
        let shape = try gate("""
        struct H {
            func update(file: File, user: User) async throws {
                guard file.canWrite(user) else { throw Abort(.forbidden) }
                try await file.save(on: db)
            }
        }
        """)
        #expect(shape == nil)
    }

    @Test("A permission guard that returns is still NOT a gate (verb, M5)")
    func permissionGuardThatReturnsIsNotAGate() throws {
        // `guard canAccess else { return }` — `canAccess` is authorisation, not a
        // claim-once capability, so it is excluded from the capability prefixes.
        let shape = try gate("""
        struct H {
            func handle(user: User) async throws {
                guard user.canAccess else { return }
                try await repo.insert(user)
            }
        }
        """)
        #expect(shape == nil)
    }

    @Test("A plain validation guard is not a dedup gate (precision)")
    func validationGuardIsNotADedupGate() throws {
        // `if x < 0 { return 0 }` returns early but names no dedup/fetch verb.
        let shape = try gate("""
        struct H {
            func clamp(_ x: Int) throws -> Int {
                if x < 0 { return 0 }
                return x
            }
        }
        """)
        #expect(shape == nil)
    }

    @Test("An off-list boolean property is not a state-flag gate (precision)")
    func offListFlagIsNotAGate() throws {
        // `isEmpty` is member-access-shaped like `isDeleted` but is a guard, not a
        // dedup flag — the curated set is what keeps it from firing.
        let shape = try gate("""
        struct H {
            func process(_ items: [Int]) throws -> Int {
                if items.isEmpty { return 0 }
                return items.count
            }
        }
        """)
        #expect(shape == nil)
    }

    @Test("A pure sync function is gated out before the walk")
    func pureSyncFunctionIsGatedOut() throws {
        // Not throws/async → couldCarryDedupGate is false → never classified,
        // even though it has an early-return-shaped `if`.
        let shape = try gate("""
        struct H {
            func firstPositive(_ xs: [Int]) -> Int {
                if let hit = xs.first(where: { $0 > 0 }) { return hit }
                return 0
            }
        }
        """)
        #expect(shape == nil)
    }
}
