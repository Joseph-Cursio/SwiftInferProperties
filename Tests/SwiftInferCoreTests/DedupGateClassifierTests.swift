@testable import SwiftInferCore
import Testing

/// The body walker behind `Signal.Kind.replayDedupGate` — `DedupGateClassifier`,
/// read off a real parse via the scanner, exactly as `ReplayIdempotenceTemplate`
/// Branch C reads it. The SwiftIdempotency handler shapes are the acceptance set;
/// the ungated twin and a plain validation guard are the refutations that keep the
/// detector from firing on every `if … return`.
@Suite("DedupGateClassifier — dedup gates read off a parsed body")
struct DedupGateClassifierTests {

    private func gate(_ source: String) throws -> DedupGateShape? {
        let summaries = FunctionScanner.scanCorpus(source: source, file: "S.swift").summaries
        return try #require(summaries.first).bodySignals.dedupGateShape
    }

    @Test("Early-return dedup gate is detected, keyed on its argument root")
    func earlyReturnDedupDetected() throws {
        // OrderCreatedHandler.handle shape.
        let shape = try gate("""
        struct H {
            func handle(_ order: Order) async throws -> Bool {
                if await dedup.hasHandled(orderID: order.id) { return false }
                try await repo.insert(order)
                return true
            }
        }
        """)
        #expect(shape == .earlyReturnDedup(keyRoot: "order"))
    }

    @Test("Fetch-then-insert gate is detected")
    func fetchThenInsertDetected() throws {
        // OfflineManager.download shape (fetch existing, return on hit, else insert).
        let shape = try gate("""
        struct H {
            func download() throws -> Row {
                if let existing = try context.fetch(descriptor).first { return existing }
                context.insert(row)
                return row
            }
        }
        """)
        #expect(shape == .fetchThenInsert)
    }

    @Test("Ungated handler yields no gate (the buggy twin)")
    func ungatedHandlerHasNoGate() throws {
        // BuggyOrderHandler.handle — the effect runs unconditionally.
        let shape = try gate("""
        struct H {
            func handle(_ order: Order) async throws -> Bool {
                try await repo.insert(order)
                return true
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
