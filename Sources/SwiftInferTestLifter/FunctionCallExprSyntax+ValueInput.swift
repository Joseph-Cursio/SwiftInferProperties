import SwiftSyntax

extension FunctionCallExprSyntax {

    /// The expression this call consumes — **from either argument position or receiver
    /// position**.
    ///
    /// ## The gap this closes
    ///
    /// The round-trip detectors read the consumed value as `arguments.first`, which models
    /// `backward(forward(x))` and nothing else. The dominant Swift spelling of a parse/print
    /// pair is a **method chain**, where the value travels through the receiver and the
    /// argument list is empty:
    ///
    /// ```swift
    /// #expect(Cfg.parse(sample).serialized() == sample)   // arguments.first == nil
    /// #expect(decode(encode(x)) == x)                     // arguments.first == the inner call
    /// ```
    ///
    /// Measured on `SwiftFormatRuleStudioCore`: `SwiftFormatConfigTests.roundTrip` states the
    /// top-scoring suggestion's law byte-exactly and contributed **zero** cross-validation
    /// signals across 19 picks (`docs/measurements/exploratory-swiftformatrulestudio.md`
    /// §5.2). The `+20` seam exists to reward a codebase that already states its laws, and it
    /// was unreachable for the way this one is written.
    ///
    /// **This is the same class as §7.3's `propertyCheck` miss, on a different axis.** That
    /// one was about the enclosing *form* a law is written in; this is about which *position*
    /// carries the value. Both made the lifter blind to house style rather than to the law.
    ///
    /// ## Why receiver-position is an argument position
    ///
    /// `x.f()` and `f(x)` denote the same application. Swift chooses between them by where the
    /// author put the type, not by what the code means — and a detector keyed on one is keyed
    /// on a spelling. This returns the receiver **only when the argument list is empty**, so a
    /// call that genuinely takes an argument is unaffected and no existing match changes.
    var consumedValueExpression: ExprSyntax? {
        if let first = arguments.first?.expression { return first }
        // Zero-argument call: the value can only have arrived through the receiver.
        guard let member = calledExpression.as(MemberAccessExprSyntax.self) else { return nil }
        return member.base
    }
}

extension ExprSyntax {

    /// The source text of this expression when it denotes a **stable value reference**, or
    /// `nil` when it denotes a computation.
    ///
    /// ## Why text, and why only these forms
    ///
    /// The collapsed round-trip shape has to decide that two expressions name the same value:
    /// `f(x).g() == x`. It did that by requiring a `DeclReferenceExprSyntax` on both sides and
    /// comparing `baseName`, which admits a local `let` and nothing else — so the two
    /// commonest ways to write a fixture input are invisible:
    ///
    /// ```swift
    /// #expect(Cfg.parse(Self.sample).serialized() == Self.sample)   // member access
    /// #expect(Cfg.parse("--indent 4").serialized() == "--indent 4") // literal
    /// ```
    ///
    /// The first is the measured witness — `SwiftFormatConfigTests` writes exactly that.
    ///
    /// **A call expression is deliberately excluded, and that exclusion is the precision
    /// mechanism.** Comparing arbitrary expression text would match
    /// `f(makeValue()).g() == makeValue()`, which states a law only if `makeValue` is
    /// deterministic — and if it is not, the lifter would report a codebase as corroborating a
    /// law it never asserted. A reference or a literal denotes the same value on both sides by
    /// construction; a call does not.
    ///
    /// Trimmed rather than fully normalised: these are two expressions from one assertion, so
    /// they are formatted alike, and an intra-expression whitespace normaliser would be
    /// machinery earning nothing.
    var stableValueReferenceText: String? {
        if self.is(DeclReferenceExprSyntax.self) { return trimmedDescription }
        if self.is(StringLiteralExprSyntax.self)
            || self.is(IntegerLiteralExprSyntax.self)
            || self.is(FloatLiteralExprSyntax.self)
            || self.is(BooleanLiteralExprSyntax.self) {
            return trimmedDescription
        }
        if let member = self.as(MemberAccessExprSyntax.self) {
            // `Self.sample` and `Fixtures.config.text` qualify; `loader().text` does not —
            // walk the base chain and refuse if any link computes.
            var base = member.base
            while let current = base {
                if current.is(DeclReferenceExprSyntax.self) { return trimmedDescription }
                guard let inner = current.as(MemberAccessExprSyntax.self) else { return nil }
                base = inner.base
            }
            // A bare `.foo` implicit-member reference has no base — not a value reference.
            return nil
        }
        return nil
    }
}
