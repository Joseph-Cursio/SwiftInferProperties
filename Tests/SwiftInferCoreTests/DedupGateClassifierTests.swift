@testable import SwiftInferCore
import Testing

/// The body walker behind `Signal.Kind.replayDedupGate` — `DedupGateClassifier`,
/// read off a real parse via the scanner, exactly as `ReplayIdempotenceTemplate`
/// Branch C reads it. The SwiftIdempotency handler shapes are the acceptance set;
/// the ungated twin and a plain validation guard are the refutations that keep the
/// detector from firing on every `if … return`.
/// Reads the `dedupGateShape` off a body parsed via the scanner — exactly as
/// `ReplayIdempotenceTemplate` Branch C reads it. Shared by both suites below.
private func gate(_ source: String) throws -> DedupGateShape? {
    let summaries = FunctionScanner.scanCorpus(source: source, file: "S.swift").summaries
    return try #require(summaries.first).bodySignals.dedupGateShape
}

/// Reads the `buildsIdempotencyKey` marker (M6) off a parsed body.
private func buildsKey(_ source: String) throws -> Bool {
    let summaries = FunctionScanner.scanCorpus(source: source, file: "S.swift").summaries
    return try #require(summaries.first).bodySignals.buildsIdempotencyKey
}

@Suite("DedupGateClassifier — dedup gates read off a parsed body")
struct DedupGateClassifierTests {

    @Test("Key-from-entity builder is detected (StripeWebhookHandler, M6)")
    func keyFromEntityBuilderDetected() throws {
        // StripeWebhookHandler.makeChargeRequest: a pure builder constructing an
        // IdempotencyKey from its input's stable id.
        let builds = try buildsKey("""
        enum H {
            static func makeChargeRequest(for event: PaymentIntent) -> ChargeRequest {
                ChargeRequest(amount: event.amount, idempotencyKey: IdempotencyKey(fromEntity: event))
            }
        }
        """)
        #expect(builds)
    }

    @Test("A plain builder that constructs no IdempotencyKey is not flagged")
    func plainBuilderIsNotFlagged() throws {
        // PricingCalculator shape — value idempotence's turf, not this branch.
        let builds = try buildsKey("""
        enum H {
            static func priceInCents(kg: Int, rate: Int) -> Int { kg * rate }
        }
        """)
        #expect(builds == false)
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
                try await file.save(on: db)
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
                try await created.save(on: req.db)
                return Row(created)
            }
        }
        """)
        #expect(shape == .fetchThenInsert)
    }

    @Test("Effect-less getter is NOT a gate (M4 — the Vernissage false positives)")
    func effectLessGetterIsNotAGate() throws {
        // getReblogStatus shape: fetch, return on hit, no insert/save anywhere.
        // A read, not a dedup-gated handler — must not fire.
        let shape = try gate("""
        struct H {
            func getStatus(id: Int, on db: Database) async throws -> Status? {
                let status = try await Status.query(on: db).first()
                if let status { return status }
                return nil
            }
        }
        """)
        #expect(shape == nil)
    }

    @Test("Task.isCancelled early return is NOT a gate (M4 — the penny false positives)")
    func taskCancellationIsNotAGate() throws {
        // penny run() shape: `if Task.isCancelled { return }` then effectful work.
        // Cancellation is not dedup; `isCancelled` was dropped from the flag set.
        let shape = try gate("""
        struct H {
            func run() async throws {
                if Task.isCancelled { return }
                try await self.publish(event)
            }
        }
        """)
        #expect(shape == nil)
    }

    @Test("An effect BEFORE the gate is not dominated by it — not a gate (M7)")
    func effectBeforeGateIsNotDominated() throws {
        // The effect runs unconditionally FIRST, then a too-late dedup check. A
        // replay re-runs the insert, so the handler is not idempotent — the gate
        // dominates nothing after it.
        let shape = try gate("""
        struct H {
            func handle(_ order: Order) async throws {
                try await repo.insert(order)
                if await dedup.hasHandled(order.id) { return }
            }
        }
        """)
        #expect(shape == nil)
    }

    @Test("An effect inside a fetch-or-create gate's branches still counts (M7 not over-strict)")
    func effectInsideGateBranchesCounts() throws {
        // Vernissage `mute` shape: `if let existing { update; save; return } else
        // { create; save }` — the effect is in the gate's own branches, at the gate,
        // not strictly before it, so dominance holds.
        let shape = try gate("""
        struct H {
            func mute(id: Int, on db: Database) async throws -> Row {
                if let existing = try await Row.query(on: db).first() {
                    existing.value = 1
                    try await existing.save(on: db)
                    return existing
                }
                let row = Row(id: id)
                try await row.save(on: db)
                return row
            }
        }
        """)
        #expect(shape == .fetchThenInsert)
    }

    @Test("An ungated accumulator before the gate vetoes it (M8)")
    func ungatedAccumulatorBeforeGateVetoes() throws {
        // `self.callCount += 1` runs on every call, before the gate — a replay
        // grows it, so the handler is not idempotent despite the gate.
        let shape = try gate("""
        struct H {
            func handle(_ order: Order) async throws {
                self.callCount += 1
                if await dedup.hasHandled(order.id) { return }
                try await repo.insert(order)
            }
        }
        """)
        #expect(shape == nil)
    }

    @Test("An accumulator AFTER the gate is fine — it is dominated (M8 not over-strict)")
    func accumulatorAfterGateIsFine() throws {
        // `self.processed.append(order)` runs only when the gate did not fire, so
        // it is the guarded effect — the gate dominates it.
        let shape = try gate("""
        struct H {
            func handle(_ order: Order) async throws {
                if await dedup.hasHandled(order.id) { return }
                try await repo.insert(order)
                self.processed.append(order)
            }
        }
        """)
        #expect(shape == .earlyReturnDedup(keyRoot: "order"))
    }

    @Test("A local accumulator before the gate does not false-veto (M8 member-scoped)")
    func localAccumulatorDoesNotVeto() throws {
        // `total += line` on a LOCAL resets each call — not an observable effect,
        // so it must not veto (member-scoping: only stored mutations count).
        let shape = try gate("""
        struct H {
            func handle(_ order: Order, lines: [Int]) async throws {
                var total = 0
                for line in lines { total += line }
                if await dedup.hasHandled(order.id) { return }
                try await repo.insert(order, total: total)
            }
        }
        """)
        #expect(shape == .earlyReturnDedup(keyRoot: "order"))
    }
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
