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

    @Test("State-flag early return is a gate (MacCloud deleteFile, M3)")
    func stateFlagGuardDetected() throws {
        // MacCloud_server deleteFile: `if file.isDeleted { return .ok }` — the
        // already-handled question answered by a stored flag, not a method call.
        let shape = try gate("""
        struct H {
            func deleteFile(file: File) async throws -> Status {
                if file.isDeleted { return .ok }
                file.markAsDeleted()
                return .ok
            }
        }
        """)
        #expect(shape == .stateFlagGuard(flag: "isDeleted"))
    }

    @Test("Pre-fetched content-addressed dedup is a gate (MacCloud restore, M3)")
    func preFetchedDedupDetected() throws {
        // MacCloud_server restoreFileVersion: fetch upstream, then re-bind and
        // compare content before returning the existing row.
        let shape = try gate("""
        struct H {
            func restore(req: Request) async throws -> Row {
                let latest = try await FileVersion.query(on: req.db).first()
                if let latest, latest.hash == version.hash { return Row(latest) }
                let created = FileVersion(hash: version.hash)
                return Row(created)
            }
        }
        """)
        #expect(shape == .fetchThenInsert)
    }

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
