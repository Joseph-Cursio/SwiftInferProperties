/// Carrier-type discriminator for the seeded verification-stub emitters.
///
/// Maps a carrier type name to the concrete numeric domain a stub generates
/// values over. Previously copy-pasted as a `private enum` in each of the
/// RoundTrip / Idempotence / Commutativity / Associativity emitters; hoisted
/// here once the fourth copy appeared.
///
/// Distinct from `StrategistDispatchEmitter`'s basis-carrier model and from
/// `ReducerCarrierKind` (action-sequence emitter) — those intentionally model
/// different carrier sets.
enum CarrierKind {
    case complexDouble
    case double
    case int

    static func from(typeName: String) -> Self? {
        switch typeName {
        case "Complex<Double>": return .complexDouble
        case "Double": return .double
        case "Int": return .int
        default: return nil
        }
    }
}
