import Foundation

// The container-carrier laws (Optional / Dictionary / Stack / Queue) plus the
// shared `law` / `caveat` builders, split out of `StandardLibraryProperties.swift`
// to keep each file under the `file_length` cap. No behavior change — `all`
// (in the primary file) aggregates these groups exactly as before.
extension StandardLibraryProperties {

    // Optional — the functor laws (identity + composition) and the monad
    // right-identity. Universally true; `Int?` is Equatable so `--verify` runs
    // them directly. None witnesses a kit ALGEBRAIC protocol (functor/monad
    // laws aren't Semigroup/Monoid/…), so all tag none — and none anchors
    // (no `functor` template exists), so all are `.reference`.
    static let optionalLaws: [KnownProperty] = [
        law(
            "Optional", "functor identity", "o.map { $0 } == o",
            "let o = randOpt(); return o.map { $0 } == o"
        ),
        law(
            "Optional", "functor composition",
            "o.map(f).map(g) == o.map { g(f($0)) }",
            "let o = randOpt(); return o.map { $0 + 1 }.map { $0 * 2 } == o.map { ($0 + 1) * 2 }"
        ),
        law(
            "Optional", "monad right identity", "o.flatMap { Optional($0) } == o",
            "let o = randOpt(); return o.flatMap { Optional($0) } == o"
        )
    ]

    // Dictionary — the mapValues functor laws, filter idempotence, and the
    // merge-with-self identity. `merging` is NOT commutative on key collisions
    // (see caveats).
    static let dictionaryLaws: [KnownProperty] = [
        law(
            "Dictionary", "mapValues functor identity", "d.mapValues { $0 } == d",
            "let d = randDict(); return d.mapValues { $0 } == d"
        ),
        law(
            "Dictionary", "mapValues functor composition",
            "d.mapValues(f).mapValues(g) == d.mapValues { g(f($0)) }",
            "let d = randDict(); "
                + "return d.mapValues { $0 + 1 }.mapValues { $0 * 2 } == d.mapValues { ($0 + 1) * 2 }"
        ),
        law(
            "Dictionary", "idempotent under filter",
            "d.filter(p).filter(p) == d.filter(p)",
            "let d = randDict(); "
                + "return d.filter { $0.value > 0 }.filter { $0.value > 0 } == d.filter { $0.value > 0 }"
        ),
        law(
            "Dictionary", "merge-with-self identity (keep first)",
            "d.merging(d) { a, _ in a } == d",
            "let d = randDict(); return d.merging(d, uniquingKeysWith: { a, _ in a }) == d"
        )
    ]

    // Stack — the LIFO contract, realized on `Array` (`append` / `removeLast`).
    // Not a stdlib type; these document the contract a user's own `Stack` owes,
    // verified against the canonical Array realization so the stdlib anchor has a
    // ground truth to match a discovered `push`/`pop` pair against.
    static let stackLaws: [KnownProperty] = [
        law(
            "Stack", "LIFO via append/removeLast", "push x then pop ⇒ x, and the stack is restored",
            "let a = randArr(); var s = a; let x = randInt(); "
                + "s.append(x); let top = s.removeLast(); return top == x && s == a"
        ),
        law(
            "Stack", "LIFO via append/removeLast", "the last pushed is the first popped",
            "var s = randArr(); let x = randInt(), y = randInt(); s.append(x); s.append(y); "
                + "return s.removeLast() == y && s.removeLast() == x"
        )
    ]

    // Queue — the FIFO contract, realized on `Array` (`append` / `removeFirst`).
    // Same framing as Stack: the contract a user's `Queue` owes, anchored to the
    // Array realization.
    static let queueLaws: [KnownProperty] = [
        law(
            "Queue", "FIFO via append/removeFirst", "enqueue adds at the back; the front dequeues first",
            "let a = randArr(); var q = a; let x = randInt(); q.append(x); "
                + "let front = q.removeFirst(); return front == (a.isEmpty ? x : a.first!)"
        ),
        law(
            "Queue", "FIFO via append/removeFirst", "the first enqueued is the first dequeued",
            "var q = [Int](); let x = randInt(), y = randInt(); q.append(x); q.append(y); "
                + "return q.removeFirst() == x && q.removeFirst() == y"
        )
    ]

    // MARK: - Builders

    static func law(
        _ type: String,
        _ structure: String,
        _ statement: String,
        _ checkBody: String,
        witnesses: String? = nil,
        template: String? = nil,
        note: String? = nil
    ) -> KnownProperty {
        KnownProperty(
            type: type, structure: structure, statement: statement,
            kind: .law, role: template != nil ? .anchor : .reference,
            witnesses: witnesses, template: template, note: note, checkBody: checkBody
        )
    }

    static func caveat(
        _ type: String,
        _ statement: String,
        _ note: String,
        template: String? = nil
    ) -> KnownProperty {
        KnownProperty(
            type: type, structure: statement, statement: statement,
            kind: .caveat, role: template != nil ? .anchor : .reference,
            witnesses: nil, template: template, note: note, checkBody: nil
        )
    }
}
