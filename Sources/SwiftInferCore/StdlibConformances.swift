/// V1.7.1 — curated stdlib-conformance bake-in.
///
/// Hosts `ProtocolCoverageMap.stdlibConformances` and its three private
/// helper sets (`signedIntegerBase` / `unsignedIntegerBase` /
/// `floatingPointBase`) as a `ProtocolCoverageMap` extension. Split out
/// of `ProtocolCoverageMap.swift` for the SwiftLint 400-line file
/// budget per the V1.5.2/V1.6.1 split precedent — `inheritedTypesIndex`
/// stays on the primary file alongside the helper, and this file owns
/// only the curated data table.
///
/// **Cycle-4 priority #1.** Closes cycle-2's headline 0-delta finding
/// on stdlib-typed (`Int` / `Double` / etc.) carriers across
/// OrderedCollections / Algorithms / PropertyLawKit. Per-key
/// `formUnion` semantics in `inheritedTypesIndex(from:)` mean a
/// corpus `extension Int: SomeProto` adds `SomeProto` to `Int`'s
/// curated set rather than replacing it.

extension ProtocolCoverageMap {

    /// V1.7.1 — curated table of stdlib types whose conformances are
    /// both unconditional and well-known. Folded into
    /// `inheritedTypesIndex(from:)`'s output so a `let x: Int`
    /// candidate resolves to the same coverage set the user would
    /// write by hand (`extension Int: AdditiveArithmetic` is implicit
    /// in Swift's stdlib; the textual scan can't see it without help).
    ///
    /// **What this closes.** Cycle-2's headline 0-delta finding on
    /// OrderedCollections / Algorithms / PropertyLawKit: V1.5.2's
    /// `inheritedTypesIndex(...)` only saw types the corpus declared;
    /// stdlib-typed `(Int, Int) -> Int` ops never reached the
    /// coverage veto because `Int` had no entry. With this bake-in,
    /// `assumedCoverageSignal(forTypeText: "Int", ...)` now finds the
    /// `AdditiveArithmetic` / `Numeric` / `Comparable` / `Hashable`
    /// / `Codable` conformances and suppresses correctly.
    ///
    /// **What this doesn't close.** Conditional conformance
    /// (`Array<T>: Equatable where T: Equatable`) is intentionally
    /// out of scope — the textual scan can't tell whether a generic
    /// argument satisfies a constraint without semantic resolution.
    /// Mirrors `EquatableResolver`'s same v1 limitation. v1.1
    /// constraint-engine territory (PRD §20.2). User-defined
    /// protocols inheriting from a curated stdlib type
    /// (`MyAlgebra: Numeric`) also don't get reach — `Int: Numeric`
    /// only helps when the candidate's `typeText` resolves textually
    /// to `Int`.
    ///
    /// **Why these 14 keys.** The integer family (`Int*` / `UInt*`),
    /// floating-point family (`Float` / `Double`), `Bool`, and
    /// `String`. All four families have stable, unconditional
    /// conformances documented in the Swift stdlib. `Float80` /
    /// `Float16` are deliberately excluded — they're
    /// platform-conditional (Float80 is x86_64-only; Float16 is
    /// ARM-only on Apple, Swift 5.4+). `Optional<T>` / `Array<T>` /
    /// `Set<T>` / `Dictionary<K,V>` / tuples are conditional on
    /// element/key types and excluded for the same v1 limitation.
    ///
    /// **Conformance entries.** Each entry lists the protocols the
    /// type textually conforms to. Parent protocols
    /// (`BinaryInteger`, `FloatingPoint`, etc.) are included even
    /// when they're not in `protocolCoverage`'s key set — they
    /// document the conformance shape and let future cycles extend
    /// the coverage table without touching the bake-in. `Equatable`
    /// is included transitively even though all listed conformances
    /// refine it — explicit beats implicit for a curated table.
    public static let stdlibConformances: [String: Set<String>] = [
        // Signed integer family — Int / Int8 / Int16 / Int32 / Int64
        "Int": signedIntegerBase,
        "Int8": signedIntegerBase,
        "Int16": signedIntegerBase,
        "Int32": signedIntegerBase,
        "Int64": signedIntegerBase,

        // Unsigned integer family — UInt / UInt8 / UInt16 / UInt32 / UInt64
        "UInt": unsignedIntegerBase,
        "UInt8": unsignedIntegerBase,
        "UInt16": unsignedIntegerBase,
        "UInt32": unsignedIntegerBase,
        "UInt64": unsignedIntegerBase,

        // Floating-point family — Float / Double
        "Float": floatingPointBase,
        "Double": floatingPointBase,

        // Other primitives — Bool / String
        "Bool": [
            "Equatable", "Hashable", "Codable"
        ],
        "String": stringCollectionBase.union([
            "Equatable", "Comparable", "Hashable", "Codable"
        ]),
        "Substring": stringCollectionBase.union([
            "Equatable", "Comparable", "Hashable"
        ]),

        // Collection family. UNCONDITIONAL conformances only — see
        // `arrayCollectionBase`.
        "Array": arrayCollectionBase,
        "ContiguousArray": arrayCollectionBase,
        "ArraySlice": arrayCollectionBase,
        "Set": [
            "Sequence", "Collection", "SetAlgebra", "ExpressibleByArrayLiteral"
        ],
        "Dictionary": [
            "Sequence", "Collection", "ExpressibleByDictionaryLiteral"
        ]
    ]

    /// The **unconditional** conformances of `Array` / `ContiguousArray` / `ArraySlice`.
    ///
    /// **Why collections were missing until 2026-08-01, and why this is the shape of the
    /// fix.** The bake-in was added in V1.7.1 to close a *numeric* finding — its own doc
    /// says "stdlib-typed (`Int` / `Double` / etc.) carriers" — and collections were never
    /// in scope. Nobody revisited it as the conformance index acquired consumers, and by
    /// the time `OrderedCarrierDiscriminator` started reading it there were twelve.
    ///
    /// The symptom that surfaced it: the discriminator asks whether a carrier's order is
    /// part of its value, and answers from conformances. In a **library** corpus `Array`'s
    /// conformances are declared in the tree being scanned, so it works. In an
    /// **application** corpus they are not, so the discriminator abstained on `Array` and
    /// only the curated `OrderSensitiveCarrierNames` denylist stood between a user-written
    /// `extension Array { func union }` and a false commutativity law.
    ///
    /// **Deliberately no `Equatable` / `Hashable` / `Codable`.** Those are *conditional* on
    /// this family (`Array<T>: Equatable where T: Equatable`), and this table's own note
    /// already rules conditional conformance out of scope: "the textual scan can't tell
    /// whether a generic argument satisfies a constraint without semantic resolution."
    /// Adding them would contradict a recorded decision *and* silently drop the `Equatable`
    /// caveat from every `Array`-carried suggestion on the strength of a guess. Every
    /// protocol below is unconditional, so no such judgement is being made.
    ///
    /// `Range` / `ClosedRange` are absent for the same reason: their `Collection`
    /// conformance is conditional on `Bound: Strideable`.
    private static let arrayCollectionBase: Set<String> = [
        "Sequence",
        "Collection",
        "BidirectionalCollection",
        "RandomAccessCollection",
        "MutableCollection",
        "RangeReplaceableCollection",
        "ExpressibleByArrayLiteral"
    ]

    /// `String` / `Substring`'s unconditional collection refinements. Both are
    /// `BidirectionalCollection` but **not** `RandomAccessCollection` (grapheme breaking
    /// makes index offsetting linear) and not `ExpressibleByArrayLiteral`, which is why
    /// the sequence-view model law continues to abstain on them while the commutativity
    /// veto now reaches them.
    private static let stringCollectionBase: Set<String> = [
        "Sequence",
        "Collection",
        "BidirectionalCollection",
        "RangeReplaceableCollection",
        "StringProtocol"
    ]

    // Deliberately differs from `unsignedIntegerBase` — see that constant's note: signedness
    // is the whole point of the split, so the two can never be the same set.
    // swiftprojectlint:disable:next parallel-list-drift
    /// V1.7.1 — shared conformance set for signed integer types.
    /// `BinaryInteger` / `FixedWidthInteger` / `SignedInteger` are
    /// included for documentation even though only their parent
    /// conformances (`Numeric` / `AdditiveArithmetic` /
    /// `SignedNumeric` / `Comparable` / `Hashable` / `Codable` /
    /// `Equatable`) currently appear in `protocolCoverage`'s key
    /// set.
    private static let signedIntegerBase: Set<String> = [
        "Equatable", "Comparable", "Hashable", "Codable",
        "AdditiveArithmetic", "Numeric", "SignedNumeric",
        "BinaryInteger", "FixedWidthInteger", "SignedInteger"
    ]

    // The documented difference above (`UnsignedInteger` vs `SignedInteger`, no
    // `SignedNumeric`) is the reason this constant exists; near-identity is expected.
    // swiftprojectlint:disable:next parallel-list-drift
    /// V1.7.1 — shared conformance set for unsigned integer types.
    /// Differs from `signedIntegerBase` only in `UnsignedInteger`
    /// vs `SignedInteger` and the absence of `SignedNumeric`.
    private static let unsignedIntegerBase: Set<String> = [
        "Equatable", "Comparable", "Hashable", "Codable",
        "AdditiveArithmetic", "Numeric",
        "BinaryInteger", "FixedWidthInteger", "UnsignedInteger"
    ]

    /// V1.7.1 — shared conformance set for floating-point types.
    /// Includes `BinaryFloatingPoint` / `FloatingPoint` for
    /// documentation; cycle-5's `KitFloatingPointTemplate` arm is
    /// the natural consumer when those keys land in
    /// `protocolCoverage`.
    private static let floatingPointBase: Set<String> = [
        "Equatable", "Comparable", "Hashable", "Codable",
        "AdditiveArithmetic", "Numeric", "SignedNumeric",
        "FloatingPoint", "BinaryFloatingPoint"
    ]
}
