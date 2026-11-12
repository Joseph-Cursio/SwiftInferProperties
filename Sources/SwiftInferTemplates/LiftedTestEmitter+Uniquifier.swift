import SwiftInferCore

extension LiftedTestEmitter {

    /// What the `uniquifier` stub calls, already spelled by the accept path.
    public struct UniquifierStub: Sendable {
        /// The subject's name as an identifier, for the test function's name.
        public let identifierName: String
        /// The subject as a reader would grep for it, for the failure message.
        public let displaySignature: String
        /// The statement that builds the state once per trial: `let subject = Namer()`, or
        /// `var state: Set<String> = []`.
        public let binding: String
        /// One call, with the drawn name spelled `name`: `subject.fresh(name)`.
        public let call: String
        /// The match: its shape gives the law's form, the alphabet's decoration and the sentinel.
        public let match: UniquifierMatch

        /// Creates the description.
        public init(
            identifierName: String,
            displaySignature: String,
            binding: String,
            call: String,
            match: UniquifierMatch
        ) {
            self.identifierName = identifierName
            self.displaySignature = displaySignature
            self.binding = binding
            self.call = call
            self.match = match
        }
    }

    /// The stub for the uniquifier law (#669): one receiver per trial, called once per drawn name, and every
    /// result distinct; or, when the body memoizes, equal keys giving equal ids and distinct keys distinct ids.
    ///
    /// The draws collide on purpose. The law fails only where one drawn name equals another plus the body's
    /// decoration, so half the trials draw 1–16 names over `a` and `b`, bare or decorated, and half draw a
    /// dense 11–24 over two names and their first decoration, so a counter reaches 10 within one trial
    /// (#692, condition 3; the census's prototype draws the same way).
    public static func uniquifierLaw(_ stub: UniquifierStub, seed: SamplingSeed.Value) -> String {
        let memoizing = stub.match.shape.isMemoizing
        let check = memoizing ? memoizingCheck(stub) : distinctCheck(stub)
        let checkName = memoizing ? "firstMismatch" : "firstCollision"
        let testName = memoizing ? "givesEqualIdsExactlyForEqualKeys" : "issuesDistinctResults"
        let failure = memoizing ? "gave ids that do not follow its keys" : "issued one result twice"
        let (wide, dense) = uniquifierAlphabet(stub.match.shape.decoration)
        return """

        @Test func \(stub.identifierName)_\(testName)() async {
            // A narrow alphabet on purpose (#692): the law fails only where one drawn name equals another
            // plus the decoration, and a generator drawing realistic names never collides.
        \(check)
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
                sample: { rng in
                    let dense = Bool.random(using: &rng)
                    let pool = dense ? \(dense) : \(wide)
                    let count = Int.random(in: dense ? 11 ... 24 : 1 ... 16, using: &rng)
                    return (0 ..< count).map { _ in pool.randomElement(using: &rng) ?? "a" }
                },
                property: { names in \(checkName)(names) == nil }
            )
            if case let .failed(_, _, input, _) = result {
                Issue.record("\(escapedForLiteral(stub.displaySignature)) \(failure): \\(\(checkName)(input) ?? "")")
            }
        }
        """
    }

    /// The first pair of calls that returned one result, or `nil`.
    private static func distinctCheck(_ stub: UniquifierStub) -> String {
        let skip = stub.match.shape.sentinel.map { sentinel in
            let literal = sentinel == "nil" ? "\"nil\"" : sentinel
            return "\n            if result == \(literal) { continue }"
        } ?? ""
        return """
            let firstCollision: @Sendable ([String]) -> String? = { names in
                \(stub.binding)
                var issued: [String: Int] = [:]
                for (position, name) in names.enumerated() {
                    let result = String(describing: \(stub.call))\(skip)
                    if let earlier = issued[result] {
                        return "calls \\(earlier + 1) and \\(position + 1), on \\(names[earlier]) and \\(name), "
                            + "both returned \\(result)"
                    }
                    issued[result] = position
                }
                return nil
            }
        """
    }

    /// The first pair of keys whose equality their ids do not follow, or `nil`.
    private static func memoizingCheck(_ stub: UniquifierStub) -> String {
        """
            let firstMismatch: @Sendable ([String]) -> String? = { names in
                \(stub.binding)
                let ids = names.map { name in String(describing: \(stub.call)) }
                for later in names.indices {
                    for earlier in names.indices where earlier < later
                        && (names[earlier] == names[later]) != (ids[earlier] == ids[later]) {
                        return "keys \\(names[earlier]) and \\(names[later]) (calls \\(earlier + 1) and "
                            + "\\(later + 1)) gave ids \\(ids[earlier]) and \\(ids[later])"
                    }
                }
                return nil
            }
        """
    }

    /// The wide and dense pools, spelled from the body's decoration.
    static func uniquifierAlphabet(_ decoration: UniquifierDecoration) -> (wide: String, dense: String) {
        let suffixes: [String]
        switch decoration {
        case .counter(let prefix):
            suffixes = ["0", "1", "2", "10", "11"].map { prefix + $0 }

        case .appended(let text):
            suffixes = [text, text + text]
        }
        let wide = ["a", "b"].flatMap { base in [base] + suffixes.map { base + $0 } }
        // `a1` for a counter, as the census's prototype draws (`a`, `a1`, `b`, `b1`); `a_` for appended text.
        let firstDecorated = if case .counter = decoration { suffixes[1] } else { suffixes[0] }
        let dense = ["a", "a" + firstDecorated, "b", "b" + firstDecorated]
        func literal(_ names: [String]) -> String {
            "[" + names.map { "\"\(escapedForLiteral($0))\"" }.joined(separator: ", ") + "]"
        }
        return (literal(wide), literal(dense))
    }
}
