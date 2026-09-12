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

    public init(bareName: String, qualifier: String? = nil, argumentLabels: [String?] = []) {
        self.bareName = bareName
        self.qualifier = qualifier
        self.argumentLabels = argumentLabels
    }

    /// A bare free-function name, which is what every emitter spliced before this type existed.
    /// Present so a test fixture can go on writing `callee: "normalize"` and get the identical
    /// string back — the migration must not re-baseline the goldens it is meant to be checked by.
    public init(stringLiteral value: String) {
        self.init(bareName: value)
    }

    /// Read a callee out of one evidence row.
    ///
    /// **Instance methods are deliberately unqualified.** A static or free function is called
    /// through its type; an instance method needs a *receiver*, which these value-law templates
    /// do not generate — their shape is `f(f(x)) == f(x)` over a value of the parameter type.
    /// Prefixing an instance method with its type name would emit
    /// `EditorFormatter.selectedText(value)`, which is a different error from the one it fixes.
    /// So the qualifier is taken only when the row is not an instance method, and an instance
    /// method keeps the previous spelling until a template exists that can name its receiver.
    public init?(evidence: Evidence) {
        guard let parenIndex = evidence.displayName.firstIndex(of: "(") else { return nil }
        let name = String(evidence.displayName[..<parenIndex])
        guard !name.isEmpty else { return nil }
        self.bareName = name
        self.qualifier = evidence.isInstanceMethod ? nil : evidence.qualifiedTypeName
        self.argumentLabels = Self.labels(inDisplayName: evidence.displayName, after: parenIndex)
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
        let rendered = arguments.enumerated().map { index, argument -> String in
            guard index < argumentLabels.count, let label = argumentLabels[index] else { return argument }
            return "\(label): \(argument)"
        }
        return "\(callPrefix)\(bareName)(\(rendered.joined(separator: ", ")))"
    }

    /// How the function is named in a failure message — qualified, with its labels, the way a
    /// reader would grep for it.
    public var displaySignature: String {
        let labels = argumentLabels.map { $0.map { "\($0):" } ?? "_:" }.joined()
        return "\(callPrefix)\(bareName)(\(labels))"
    }
}
