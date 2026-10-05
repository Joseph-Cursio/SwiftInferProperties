import Foundation
import SwiftInferCore

/// The reference oracle's own declines: shapes `accept`'s determinism stub can still write, because
/// it calls only the subject, but whose `<name>_reference` twin no test can call or compare.
///
/// ## Why accept does not share them
///
/// The determinism law is `f(x) == f(x)`: the same function on both sides. The oracle's is
/// `f(x) == f_reference(x)`, with the reference declared by the scaffold in an `extension` of the
/// owner. That one difference is the whole of each decline here:
///
/// - **An opaque result.** Two calls of the same `-> some Equatable` function return one type, so
///   `f(x) == f(x)` can compile; `f_reference` declares its own opaque type, so the two sides are
///   different types whatever the protocol (*binary operator '==' cannot be applied to operands of
///   type 'some Collection' … and 'some Collection'*).
/// - **A static member of a constrained extension of a generic standard-library type.**
///   `extension Array where Element == Int { static func zeros(count: Int) -> [Int] }` is called
///   as `Array.zeros(count:)`, and Swift infers `Element` from the one extension that declares it.
///   The scan does not record the `where` clause, so the reference is declared in a plain
///   `extension Array`, and `Array.zeros_reference(count:)` fails with *generic parameter 'Element'
///   could not be inferred*.
///
/// An existential result (`any Shape`, or a scanned protocol named bare) and a static member of a
/// protocol extension fail in accept's stub too, but declining them there is an accept-output
/// change outside this scaffold's work, so they are declined here only.
extension SwiftInferCommand.Discover {

    /// Generic standard-library and Foundation types a static member may be declared on through
    /// an extension the scan cannot see the `where` clause of. Named bare: `[Int]`, `Array<Int>`
    /// and `Dictionary<String, Int>` carry their arguments and are not in this set.
    static let genericStandardLibraryTypes: Set<String> = [
        "Array", "ArraySlice", "ContiguousArray", "Set", "Dictionary", "Optional", "Result",
        "Range", "ClosedRange", "PartialRangeFrom", "PartialRangeUpTo", "PartialRangeThrough",
        "Slice", "KeyValuePairs", "CollectionOfOne", "EmptyCollection", "Repeated",
        "UnsafePointer", "UnsafeMutablePointer", "UnsafeBufferPointer", "UnsafeMutableBufferPointer",
        "KeyPath", "WritableKeyPath", "ReferenceWritableKeyPath", "AsyncStream", "AsyncThrowingStream",
        "Measurement", "OrderedSet", "OrderedDictionary", "Deque"
    ]

    /// Foreign protocols a result may name bare, as an existential: the protocols
    /// `UnequatableResultGate` already knows do not make a conformer `Equatable`, and `Error`.
    private static let foreignProtocolNames: Set<String> = UnequatableResultGate.knownNotEquatable
        .union(["Error", "LocalizedError"])

    /// Why a static member's `<Owner>.<name>_reference(…)` cannot be called, or `nil`.
    ///
    /// Two owners name no type a call can go through: a scanned protocol (*static member
    /// 'squared' cannot be used on protocol metatype*), and a generic standard-library type whose
    /// constrained extension the reference cannot repeat. A scanned type of the same name shadows
    /// the standard library's, so it is let through.
    static func staticOwnerDeclineReason(
        for summary: FunctionSummary,
        display: String,
        context: ReferenceOracleContext
    ) -> String? {
        guard summary.isStatic, let owner = summary.qualifiedContainingTypeName else { return nil }
        if context.protocolNames.contains(owner) {
            return "\(display) is a static member of the protocol `\(owner)`, and a static member cannot "
                + "be called on a protocol, only on a type conforming to it"
        }
        if genericStandardLibraryTypes.contains(owner), context.typeShapesByName[owner] == nil {
            return "\(display) is a static member of an extension of the generic type `\(owner)`, and its "
                + "reference's extension cannot repeat that extension's `where` clause, so a call through "
                + "`\(owner)` cannot infer its type arguments"
        }
        return nil
    }

    /// Why the result is one `==` cannot compare between the subject and its reference, or `nil`:
    /// an opaque result (`some P`), or an existential — `any P`, or a protocol named bare.
    ///
    /// The result is spelled as a test file writes it first, so a scanned `Parser.Error` is not
    /// read as the standard library's `Error`.
    static func existentialResultReason(
        display: String,
        returnTypeText: String,
        owner: String?,
        context: ReferenceOracleContext
    ) -> String? {
        let words = returnTypeText.split { !($0.isLetter || $0.isNumber || $0 == "_") }
        if words.contains("some") {
            return "\(display) returns `\(returnTypeText)`, an opaque result: the reference's would be "
                + "a different type from the subject's, so `==` cannot compare them"
        }
        if words.contains("any") {
            return "\(display) returns `\(returnTypeText)`, an existential, and `==` cannot compare "
                + "two existentials"
        }
        let selfless = owner.map { SubjectCallPlan.replacingSelf(in: returnTypeText, with: $0) } ?? returnTypeText
        let spelled = TypeShapeBuilder.resolvedSpelling(
            selfless, enclosing: owner ?? "", universe: context.spellingUniverse.union(context.protocolNames)
        )
        let protocolName = UnequatableResultGate.operandTypeNames(in: spelled).first { name in
            context.protocolNames.contains(name)
                || (foreignProtocolNames.contains(name) && context.spellingUniverse.contains(name) == false)
        }
        guard let protocolName else { return nil }
        return "\(display) returns `\(returnTypeText)`, and `\(protocolName)` is a protocol, so the "
            + "result is an existential `==` cannot compare"
    }
}
