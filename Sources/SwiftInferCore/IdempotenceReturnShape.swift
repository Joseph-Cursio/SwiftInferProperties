import SwiftSyntax

/// What a `T -> T` function's **returned expression** does to its input.
///
/// An idempotent function projects onto a normal form, so its result is a
/// sub-part of its input: strip, trim, cut, dedup, sort. A function whose result
/// is *built around* its input — wrapped, appended to, path-extended — cannot be
/// idempotent, because applying it twice wraps twice. That is falsity, not low
/// confidence, which is why the consuming signal is a veto rather than a penalty
/// (the same reasoning `orderSensitiveCarrier` gives).
///
/// ## Measured before it was built
///
/// A survey on 2026-08-04 ran every `idempotence` candidate on this repo:
/// **55 executed, 13 refuted — a 24% false-law rate**, all at the score-35
/// shape-only floor. A prototype of this classifier, frozen to disk *before* the
/// verdicts existed, scored **5/5 precision** on the rows that ran when keyed on
/// the return expression alone.
///
/// ## Why the return expression ALONE
///
/// The prototype also had a body-wide fallback, and that fallback produced its
/// only false alarm: `dedupedByStateAndAction` was flagged because `.append`
/// appears in its body — but it is a *dedup*, and dedup is idempotent. Meanwhile
/// `quoted(_:)` calls `replacingOccurrences` (a normalizer marker) and *then*
/// wraps in delimiters, so a body-wide scan reads it as a normalizer and misses
/// it. **Where you look decides the answer; what you look for does not.** The
/// last thing the function does is the only thing that settles it.
public enum IdempotenceReturnShape: Sendable, Equatable {

    /// The result is built AROUND the input — wrapped in delimiters, appended
    /// to, extended by a path component. `f(f(x))` wraps twice.
    ///
    /// Carries the spelling found, for the explainability line.
    case extendsInput(via: String)

    /// The return expression was read and matched no extension shape. **Not** a
    /// claim that the function is idempotent — only that this classifier saw no
    /// reason to say it is not. The veto fires on positive detection only.
    case notExtending
}

/// Reads `IdempotenceReturnShape` off a function body.
///
/// Deliberately narrow. It answers one question — *does the returned expression
/// grow its input?* — and returns `.notExtending` for everything it does not
/// recognise, including shapes it arguably should. The measured miss class is
/// **domain transfer**: `T -> T` where the output is a different *kind* of thing
/// (a hash, a rendered name, a seed string), so `f(f(x))` is meaningless though
/// it type-checks. Six of the 13 refutations were that class and this catches
/// none of them, on purpose — it is not characterised well enough to veto on,
/// and a veto that fires on a guess suppresses true laws.
public enum IdempotenceReturnShapeClassifier {

    /// Spellings that build a larger value from a smaller one. Each is a *call
    /// or operator*, not a name — `appendingPathComponent` is what it does, and
    /// a function called `normalize` that calls it is still not idempotent.
    private static let extensionCalls: [(needle: String, label: String)] = [
        ("appendingPathComponent", "appendingPathComponent"),
        ("appendingPathExtension", "appendingPathExtension"),
        ("insertingPrefix", "insertingPrefix")
    ]

    /// Classify the body of a `T -> T` function.
    ///
    /// `nil` when there is no single returned expression to read — a body that
    /// branches to several returns is not something this wants to guess about.
    public static func classify(body: CodeBlockSyntax) -> IdempotenceReturnShape {
        guard let result = resultExpression(of: Array(body.statements)) else {
            return .notExtending
        }
        return classify(result: result)
    }

    static func classify(result: ExprSyntax) -> IdempotenceReturnShape {
        // A multi-line or interpolated string literal that CONTAINS the value:
        // `"\"\(escaped)\""`, or a source template embedding its argument. The
        // result strictly contains the input, so a second application embeds the
        // first embedding.
        if let literal = result.as(StringLiteralExprSyntax.self) {
            let interpolates = literal.segments.contains { $0.is(ExpressionSegmentSyntax.self) }
            let hasSurroundingText = literal.segments.contains { segment in
                guard let string = segment.as(StringSegmentSyntax.self) else { return false }
                return !string.content.text.isEmpty
            }
            // Interpolation ALONE is not extension — `"\(x)"` is a conversion.
            // It is interpolation plus literal text around it that grows the value.
            if interpolates, hasSurroundingText {
                return .extendsInput(via: "string literal wrapping its input")
            }
        }

        // `a + [b]`, `a + "suffix"`, `xs + [x]` — concatenation onto the input.
        //
        // Read as a **`SequenceExprSyntax`**, not `InfixOperatorExprSyntax`:
        // SwiftSyntax does not fold operators without a separate folding pass, so
        // `text + "."` arrives as the unfolded sequence [text, +, "."]. Keying on
        // the folded node silently matched nothing, which is precisely the failure
        // this classifier exists to prevent in others — a check that looks right
        // and fires never.
        if let sequence = result.as(SequenceExprSyntax.self) {
            let concatenates = sequence.elements.contains { element in
                element.as(BinaryOperatorExprSyntax.self)?.operator.text == "+"
            }
            // **At least one operand must be a LITERAL**, and this narrowing was
            // forced by two measured false vetoes rather than foreseen.
            //
            // `+` between two expressions both derived from the input is a
            // REORDERING, not a growth: `prioritised` is
            // `kernels.filter{…} + kernels.filter{…}` and `unwrappingRepetition`
            // is `Array(leading) + loopBody`. Both measured `bothPass` — they are
            // genuinely idempotent — and a bare `+` rule vetoed both. Concatenating
            // a literal is the shape that actually grows a value: `text + "."`,
            // `xs + [x]`, or a message assembled from string literals.
            let hasLiteralOperand = sequence.elements.contains { element in
                element.is(StringLiteralExprSyntax.self) || element.is(ArrayExprSyntax.self)
            }
            if concatenates, hasLiteralOperand {
                return .extendsInput(via: "concatenation of a literal onto its input")
            }
        }

        // Foundation's path/extension builders, and friends.
        let text = result.trimmedDescription
        for call in extensionCalls where text.contains(call.needle) {
            return .extendsInput(via: call.label)
        }

        return .notExtending
    }

    /// The expression whose value the function returns: an explicit trailing
    /// `return X`, or a bare expression under Swift's implicit return. Same
    /// shape as `EqualityBodyClassifier`'s, and deliberately so — both ask "what
    /// does this function finally hand back", and two spellings of that question
    /// would drift.
    private static func resultExpression(of statements: [CodeBlockItemSyntax]) -> ExprSyntax? {
        guard let last = statements.last else { return nil }
        switch last.item {
        case .stmt(let statement):
            return statement.as(ReturnStmtSyntax.self)?.expression

        case .expr(let expression):
            return expression

        case .decl:
            return nil
        }
    }
}
