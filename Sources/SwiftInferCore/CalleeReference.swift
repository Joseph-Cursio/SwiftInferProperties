/// How an emitted stub must spell a call to the function it is testing.
///
/// ## The defect this closes
///
/// Every stub emitter spliced the bare function name into its property expression:
///
/// ```swift
/// let property = "\(funcName)(\(funcName)(value)) == \(funcName)(value)"
/// ```
///
/// That is right for `normalize(_:)` at file scope and wrong for everything else. Accepting
/// every suggestion on SwiftMarkdownWiki emitted 19 stubs and **not one could compile**; the
/// calls came out as `strippingHeadingMarkers(strippingHeadingMarkers(value))`, missing both
/// the `EditorFormatter.` qualification and the `from:` argument label (#415). App code is
/// almost entirely type members, so this is the common case rather than an edge one.
///
/// ## Where the pieces come from, which is not where the issue said
///
/// #415 reported that the emitter *"already receives what it needs to qualify the call and
/// explicitly ignores it"*, pointing at `typeName _:`. That parameter is
/// `paramType(from: evidence.signature)` — the **carrier** type the generator produces, `String`
/// for `strippingHeadingMarkers(from: String)`. It is not the declaring type and never was.
///
/// The declaring type is `Evidence.qualifiedTypeName`, recorded for exactly this reason and
/// already consumed by verify. The labels are in `Evidence.displayName`, which is rendered
/// *with* them (`strippingHeadingMarkers(from:)`) and was being reduced to its bare prefix.
///
/// ## Free functions render byte-identically
///
/// `normalize(_:)` at file scope has no qualifier and one unlabelled parameter, so `call("value")`
/// produces `normalize(value)` — the same string the splice produced. That is deliberate: it
/// keeps every pre-existing golden honest rather than re-baselining them alongside a fix.
public struct CalleeReference: Sendable, Equatable, ExpressibleByStringLiteral {

    /// The function's own name, with no qualifier and no labels. Names the emitted
    /// `@Test func`, which cannot contain a dot.
    public let bareName: String

    /// The declaring type's full lexical path, or `nil` for a free function.
    public let qualifier: String?

    /// One entry per parameter, in order. `nil` is an unlabelled parameter (`_:`).
    public let argumentLabels: [String?]

    /// The global actor the callee is isolated to, or `nil`.
    public let isolation: String?

    /// `true` when the call needs a **receiver** rather than a type qualifier.
    ///
    /// `Doc.merge(lhs, rhs)` does not type-check for `func merge(_:)` — `Doc.merge` is the
    /// curried `(Doc) -> (Doc) -> Doc`. The receiver is therefore the first argument a caller
    /// supplies, which is why it costs one more than the method declares.
    public let isInstanceMethod: Bool

    /// `true` when the callee is a computed property, which is **accessed** rather than called.
    /// Emitting `value.count()` for `var count: Int` is a different error from the one
    /// qualification fixes; it cost swift-system 5 of 6 build failures on the verify side.
    public let isComputedProperty: Bool

    public init(
        bareName: String,
        qualifier: String? = nil,
        argumentLabels: [String?] = [],
        isolation: String? = nil,
        isInstanceMethod: Bool = false,
        isComputedProperty: Bool = false
    ) {
        self.bareName = bareName
        self.qualifier = qualifier
        self.argumentLabels = argumentLabels
        self.isolation = isolation
        self.isInstanceMethod = isInstanceMethod
        self.isComputedProperty = isComputedProperty
    }

    /// Operators are never qualified and never take labels: `Money.+` is not a spelling, while
    /// `+(lhs, rhs)` is. Kept as its own question rather than folded into the qualifier rule,
    /// because the two have different reasons.
    static func isOperatorName(_ name: String) -> Bool {
        let operatorCharacters: Set<Character> = [
            "+", "-", "*", "/", "%",
            "<", ">", "=", "!",
            "&", "|", "^", "~", "?"
        ]
        guard !name.isEmpty else { return false }
        return name.allSatisfy(operatorCharacters.contains)
    }

    /// A bare free-function name, which is what every emitter spliced before this type existed.
    /// Present so a test fixture can go on writing `callee: "normalize"` and get the identical
    /// string back — the migration must not re-baseline the goldens it is meant to be checked by.
    public init(stringLiteral value: String) {
        self.init(bareName: value)
    }

    /// Read a callee out of one evidence row.
    ///
    /// **An instance method takes a receiver, not a qualifier.** `EditorFormatter.selectedText(x)`
    /// is a different error from the one qualification fixes — it is the curried
    /// `(EditorFormatter) -> (X) -> R`. So `qualifier` stays `nil` and the receiver arrives as
    /// the first argument the template applies, which is what makes `applicationArity` one more
    /// than the method declares.
    ///
    /// An earlier version of this type left instance methods spelled bare, "until a template
    /// exists that can name its receiver". That was wrong twice over: the templates that apply
    /// two arguments could always name one, and a bare spelling is not a deferral but an
    /// uncompilable stub. Measured on SwiftMarkdownWiki, it emitted
    /// `filtered(filtered(value))` and `union(pair.0, pair.1)` for two `private func`s — one of
    /// which #440 then wrapped in an actor hop, correctly, around a call that was never
    /// callable. `PR #441` reached the same conclusion independently from a 21-corpus sweep.
    public init?(evidence: Evidence) {
        guard let parenIndex = evidence.displayName.firstIndex(of: "(") else { return nil }
        let name = String(evidence.displayName[..<parenIndex])
        guard !name.isEmpty else { return nil }
        // A mutating method returns `Void` and edits in place, so it is not the value-returning
        // shape any of these laws states. Declining is the whole point: the alternative is a
        // stub that reads `value.normalize() == value.normalize()` over two `()`s.
        guard !evidence.isMutatingMethod else { return nil }
        self.bareName = name
        self.isInstanceMethod = evidence.isInstanceMethod
        self.isComputedProperty = evidence.isComputedProperty
        if Self.isOperatorName(name) {
            self.qualifier = nil
        } else {
            self.qualifier = evidence.isInstanceMethod ? nil : evidence.qualifiedTypeName
        }
        self.argumentLabels = Self.labels(inDisplayName: evidence.displayName, after: parenIndex)
        self.isolation = evidence.globalActor
    }

    /// A mutating instance method, read for use as a STATEMENT — `copy.formUnion(other)` — which
    /// is the one place a law may call one. `init?(evidence:)` refuses mutating methods because as
    /// a value they are `()`; the dual-style law needs exactly that call, applied to a copy and
    /// compared afterwards, so it asks for it by this name rather than weakening that guard.
    public static func mutatingStatement(evidence: Evidence) -> Self? {
        guard evidence.isMutatingMethod, evidence.isInstanceMethod,
              let parenIndex = evidence.displayName.firstIndex(of: "(") else { return nil }
        let name = String(evidence.displayName[..<parenIndex])
        guard !name.isEmpty, !isOperatorName(name) else { return nil }
        return Self(
            bareName: name,
            qualifier: nil,
            argumentLabels: labels(inDisplayName: evidence.displayName, after: parenIndex),
            isolation: evidence.globalActor,
            isInstanceMethod: true,
            isComputedProperty: false
        )
    }

    /// How many arguments a caller must supply to spell one call — the declared parameters,
    /// plus the receiver when there is one, and zero for a static computed property.
    public var applicationArity: Int {
        if isComputedProperty { return isInstanceMethod ? 1 : 0 }
        return argumentLabels.count + (isInstanceMethod ? 1 : 0)
    }

    /// Whether a template that applies `count` arguments can call this subject at all.
    ///
    /// **The reason this is a question and not an assertion.** A template's shape is fixed:
    /// `idempotence` applies one argument (`f(f(x))`), `commutativity` two (`f(a, b)`). A
    /// one-parameter *instance* method needs two — receiver plus argument — so it fits
    /// commutativity and cannot fit idempotence. Where it does not fit, the caller emits
    /// nothing. A stub that does not build costs the reader more than a suggestion they never
    /// saw, which is the measured lesson of the 89%-fails-to-compile result in
    /// `criterion-a-unmet-subject.md`.
    public func accepts(applicationArity count: Int) -> Bool {
        applicationArity == count
    }

    /// `expression`, hopped onto the callee's actor when it has one.
    ///
    /// **The hop belongs around the whole property, not around each call.** `MainActor.run`
    /// takes a *synchronous* `@MainActor` closure, so `await` cannot appear inside one — and
    /// wrapping each call individually would produce
    /// `await MainActor.run { f(await MainActor.run { f(x) }) }`, which does not compile. One
    /// hop, around the expression the law states.
    ///
    /// **And it has to be the property closure, not the test function.** Annotating the emitted
    /// `@Test` with `@MainActor` was the obvious fix and was measured first: it does not help,
    /// because the property is a `@Sendable` closure handed to a nonisolated `async` function and
    /// does not inherit the test's isolation. `PropertyBackend`'s `property` is
    /// `@Sendable (Input) async throws -> Bool` — already `async`, so the `await` needs no API
    /// change.
    public func isolated(_ expression: String) -> String {
        guard let isolation else { return expression }
        if isolation == Self.actorReceiverIsolation { return Self.awaitingEachStatement(expression) }
        return "await \(isolation).run { \(expression) }"
    }

    /// The isolation of a method on an **actor instance**, as distinct from a global actor.
    ///
    /// Such a call is reached with a bare `await`, not a hop: there is no `run` to call, and one
    /// `await` covers every call in the expression, as `try` does. Census 13 set aside 11 stubs
    /// across four repositories on *actor-isolated instance method cannot be called from outside
    /// of the actor* or a missing `await`. `actor` is a keyword, so no global actor can share the
    /// spelling. Set by the accept path only (`ActorReceiver`); never indexed.
    public static let actorReceiverIsolation = "actor"

    /// `body` with one `await` at the head of each statement's expression.
    ///
    /// A writer hands `isolated` either an expression or the `;`-joined statements of a property
    /// closure (`_ = f(x); return true`). A hop takes either inside its closure; a bare `await`
    /// does not, and cannot go on each call instead — Swift rejects `await` to the right of `==`.
    /// So it goes where each statement's expression begins: after `return `, after `_ = ` or a
    /// binding's `= `, else in front. An `await` over a statement with no actor call only warns.
    static func awaitingEachStatement(_ body: String) -> String {
        let statements = body.components(separatedBy: "; ").map(awaitingStatement)
        return statements.joined(separator: "; ")
    }

    private static func awaitingStatement(_ statement: String) -> String {
        // Totality's closing `return true` calls nothing; awaiting it only adds a warning.
        if statement == "return true" { return statement }
        if statement.hasPrefix("return ") { return "return await " + statement.dropFirst("return ".count) }
        if let range = statement.range(of: #"^(_|(let|var) \w+) = "#, options: .regularExpression) {
            return statement[range] + "await " + statement[range.upperBound...]
        }
        return "await " + statement
    }

    /// The parameter labels inside a display name's parentheses — `(from:)` is `["from"]`,
    /// `(_:_:)` is `[nil, nil]`, `()` is `[]`.
    private static func labels(inDisplayName displayName: String, after parenIndex: String.Index) -> [String?] {
        let afterParen = displayName.index(after: parenIndex)
        guard let closeIndex = displayName.lastIndex(of: ")"), afterParen <= closeIndex else { return [] }
        let inside = displayName[afterParen ..< closeIndex]
        guard !inside.isEmpty else { return [] }
        return inside.split(separator: ":", omittingEmptySubsequences: false)
            .dropLast()
            .map { $0 == "_" ? nil : String($0) }
    }

    /// `Type.` when the callee is qualified, empty otherwise.
    public var callPrefix: String { qualifier.map { "\($0)." } ?? "" }

    /// The call expression for `arguments`, in order.
    ///
    /// A label is applied only where one was recorded and an argument exists to carry it, so a
    /// row whose `displayName` lost its labels (every hand-built `Evidence` in a test fixture)
    /// renders positionally rather than wrongly.
    public func call(_ arguments: String...) -> String { call(arguments) }

    public func call(_ arguments: [String]) -> String {
        guard isInstanceMethod else {
            if isComputedProperty { return "\(callPrefix)\(bareName)" }
            return "\(callPrefix)\(bareName)(\(labelled(arguments).joined(separator: ", ")))"
        }
        // The receiver is the first argument the template supplied; the rest are the method's
        // own. A caller that has checked `accepts(applicationArity:)` always has at least one.
        guard let receiver = arguments.first else { return bareName }
        let rest = Array(arguments.dropFirst())
        if isComputedProperty { return "\(receiver).\(bareName)" }
        return "\(receiver).\(bareName)(\(labelled(rest).joined(separator: ", ")))"
    }

    /// `arguments` with each recorded label applied, positionally where none was recorded — so
    /// a row whose `displayName` lost its labels renders positionally rather than wrongly.
    private func labelled(_ arguments: [String]) -> [String] {
        arguments.enumerated().map { index, argument in
            guard index < argumentLabels.count, let label = argumentLabels[index] else { return argument }
            return "\(label): \(argument)"
        }
    }

    /// How the function is named in a failure message — qualified, with its labels, the way a
    /// reader would grep for it.
    public var displaySignature: String {
        let labels = argumentLabels.map { $0.map { "\($0):" } ?? "_:" }.joined()
        if isComputedProperty { return "\(callPrefix)\(bareName)" }
        return "\(callPrefix)\(bareName)(\(labels))"
    }
}
