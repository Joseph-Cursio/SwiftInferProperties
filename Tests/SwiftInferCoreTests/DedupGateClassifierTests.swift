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

/// Reads the `callsIdempotentWrite` marker (M10) off a parsed body.
private func writesIdempotently(_ source: String) throws -> Bool {
    let summaries = FunctionScanner.scanCorpus(source: source, file: "S.swift").summaries
    return try #require(summaries.first).bodySignals.callsIdempotentWrite
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

    @Test("Idempotent-write primitive is detected (M10 recall)")
    func idempotentWriteDetected() throws {
        // A handler whose write is an upsert — idempotent by the primitive.
        let writes = try writesIdempotently("""
        struct H {
            func record(event: Event, on db: Database) async throws {
                try await Event(id: event.id).upsert(on: db)
            }
        }
        """)
        #expect(writes)
    }

    @Test("A plain insert is NOT an idempotent write (M10 precision)")
    func plainInsertIsNotIdempotentWrite() throws {
        // `.create`/`.save` are not idempotent-by-construction — only the
        // upsert/getOrCreate family is.
        let writes = try writesIdempotently("""
        struct H {
            func record(event: Event, on db: Database) async throws {
                try await Event(id: event.id).create(on: db)
            }
        }
        """)
        #expect(writes == false)
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

    @Test("An INCREMENT in the gate's hit branch vetoes it (M11 — registerConnectionError)")
    func incrementInHitBranchVetoes() throws {
        // Vernissage registerConnectionError shape: fetch, and on a hit increment a
        // counter. A replay double-counts, so it is NOT idempotent.
        let shape = try gate("""
        struct H {
            func registerError(host: String, on db: Database) async throws {
                let server = try await Server.query(on: db).first()
                if let server {
                    server.numberOfErrors += 1
                    try await server.save(on: db)
                    return
                }
                try await Server(host: host).save(on: db)
            }
        }
        """)
        #expect(shape == nil)
    }

    @Test("A SET-update in the gate's hit branch is fine (M11 — the mute distinction)")
    func setUpdateInHitBranchIsFine() throws {
        // Vernissage mute shape: on a hit, SET fields to given values (idempotent),
        // not increment. Must still match.
        let shape = try gate("""
        struct H {
            func mute(id: Int, status: Bool, on db: Database) async throws -> Row {
                let existing = try await Row.query(on: db).first()
                if let existing {
                    existing.status = status
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
