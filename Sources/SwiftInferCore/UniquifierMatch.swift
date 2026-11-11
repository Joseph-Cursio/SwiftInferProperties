/// Where a uniquifier keeps the names it has issued (#669's criterion 1).
public enum UniquifierForm: Sendable, Equatable {
    /// A method on a class: the receiver holds the state.
    case instance
    /// A `mutating` method on a value type: the receiver holds the state, so the stub binds it with `var`.
    case mutating
    /// A function whose `inout` collection parameter holds the state, passed as `&state`.
    case inoutParameter(index: Int, collectionType: String)
}

/// An initializer whose every parameter is a collection of names (`init(reserving names: [String])`): the
/// receiver's contract owes distinct results only over the names it reserved (#692, condition 5), so the stub
/// builds it from the drawn names.
public struct UniquifierReservation: Sendable, Equatable {
    /// Each parameter's label, `nil` for `_`.
    public let labels: [String?]
    /// Each parameter's type: `[String]`, `Set<String>`.
    public let types: [String]

    /// Creates the reservation.
    public init(labels: [String?], types: [String]) {
        self.labels = labels
        self.types = types
    }
}

/// What `UniquifierTemplate` matched, carried to its stub writer (`template-match-payloads.md`: names and
/// values only, never the summary).
public struct UniquifierMatch: Sendable, Equatable {
    /// The body's shape.
    public let shape: UniquifierShape
    /// Where the state lives.
    public let form: UniquifierForm
    /// Each parameter's type text, in order.
    public let parameterTypes: [String]
    /// The one `String` parameter a drawn name goes into, or `nil` when the name enters some other way
    /// (`uniqName(item: SyntaxStructure, …)` reads `item.fullName`), so the stub leaves a placeholder.
    public let nameParameter: Int?
    /// The owner's reserving initializer, or `nil`.
    public let reservation: UniquifierReservation?

    /// Creates a match.
    public init(
        shape: UniquifierShape,
        form: UniquifierForm,
        parameterTypes: [String],
        nameParameter: Int?,
        reservation: UniquifierReservation? = nil
    ) {
        self.shape = shape
        self.form = form
        self.parameterTypes = parameterTypes
        self.nameParameter = nameParameter
        self.reservation = reservation
    }
}
