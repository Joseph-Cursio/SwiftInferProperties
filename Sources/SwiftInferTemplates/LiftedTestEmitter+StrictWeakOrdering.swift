import SwiftInferCore

/// The `comparator` arm: a `(T, T) -> Bool` owes a strict weak ordering (#475).
///
/// ## Delegated to the kit, not re-spelled
///
/// SwiftPropertyLaws' `checkStrictWeakOrderingLaws(over:by:)` checks irreflexivity, asymmetry,
/// transitivity and transitivity of incomparability, and it carries the guard a hand-spelled stub
/// would lack: a conditional law that was never applied — no chain `x < y < z` was drawn — is
/// reported through `Issue.record` rather than passed. Re-spelling the four laws here would lose
/// that and fork the definition.
///
/// ## Two passes, because the law comparators break most is the one a wide draw never reaches
///
/// Transitivity of incomparability applies only when drawn values **tie** on every compared key —
/// the clause the template calls "the one a folders-first-then-name comparator most often breaks".
/// The kit deliberately does not guard it (a total order has no ties, and is correct). So over a
/// wide draw it passes without ever being tested. **Measured** in a scratch package under Swift 6.3,
/// through this exact call over the resolver's generator for a `struct Item { isFolder: Bool;
/// name: String; size: Int }`: a comparator treating sizes within 1 as equal — incomparability not
/// transitive — **passed 5 runs of 5** at 1,000 trials each, silently; the same comparator over a
/// tie-dense draw **failed 5 of 5**, at trial 2. The reflexive `<=` and the non-transitive
/// `a > b || c < d` from the template's caveat failed under the wide draw, as they should.
///
/// So the stub runs the suite over the derived generator, then over `tieDense(_:)` of it. The
/// second pass is omitted when the rewrite changes nothing, rather than run twice on one draw.
extension LiftedTestEmitter {

    /// Emit a strict-weak-ordering test for `callee`: one kit call per generator in `passes`.
    ///
    /// - Parameter passes: `(note, generator)` pairs; the note is written above its call, one comment
    ///   line per line of note, so a reader knows why the same laws run twice.
    public static func strictWeakOrdering(
        callee: CalleeReference,
        passes: [(note: String, generator: String)]
    ) -> String {
        let compare = "{ \(callee.call("$0", "$1")) }"
        let calls = passes.map { pass in
            """
                \(pass.note.split(separator: "\n").map { "// " + $0 }.joined(separator: "\n    "))
                try await checkStrictWeakOrderingLaws(
                    over: \(pass.generator),
                    by: \(compare)
                )
            """
        }
        return """
        @Test func \(callee.bareName)_isAStrictWeakOrdering() async throws {
        \(calls.joined(separator: "\n"))
        }
        """
    }

    /// `expression` with every literal numeric and string leaf narrowed to a handful of values, so
    /// drawn values tie.
    ///
    /// Integers to `0...4`; `Double`/`Float` to the same five values as whole numbers, because a
    /// narrowed *continuous* range still almost never draws two equal values; an alphanumeric string
    /// to `CollisionBias.alphabet`, the small key universe the template's own recipe uses. `Bool` is
    /// already dense. A leaf spelled any other way is left alone — the rewrite only narrows what it
    /// recognises, the same posture as the kit suites' `boundingNumerics`.
    public static func tieDense(_ expression: String) -> String {
        tieDenseLeaves.reduce(expression) { shaped, leaf in
            shaped.replacingOccurrences(of: leaf.wide, with: leaf.dense)
        }
    }

    /// Each literal leaf `RawType.generatorExpression` emits, and its tie-dense replacement.
    private static let tieDenseLeaves: [(wide: String, dense: String)] = {
        let keys = CollisionBias.alphabet.map { "\"\($0)\"" }.joined(separator: ", ")
        let integers = ["Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64"]
            .map { type in
                let factory = type.lowercased()
                return (wide: "Gen<\(type)>.\(factory)()", dense: "Gen<\(type)>.\(factory)(in: 0...4)")
            }
        return integers + [
            (
                wide: "Gen<Character>.letterOrNumber.string(of: 0...8)",
                dense: "Gen<String?>.element(of: [\(keys)] as [String]).map { $0! }"
            ),
            (
                wide: "Gen<Double>.double(in: -1_000_000...1_000_000)",
                dense: "Gen<Int>.int(in: 0...4).map { Double($0) }"
            ),
            (
                wide: "Gen<Float>.float(in: -1_000_000...1_000_000)",
                dense: "Gen<Int>.int(in: 0...4).map { Float($0) }"
            )
        ]
    }()
}
