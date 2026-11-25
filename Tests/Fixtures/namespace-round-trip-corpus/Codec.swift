import Foundation

/// A tiny percent-style codec for path segments, on a caseless-enum namespace.
///
/// The toy that found the survey/suggestion disagreement (2026-11-24): `verify --suggestion`
/// measured `Slug.encode` / `Slug.decode` over `String` and found the planted bug below, while
/// `verify --all-from-index` filed the same round trip as `not-a-candidate: carrier Slug is a
/// caseless enum`. `NamespaceRoundTripVerifyMeasuredTests` holds both modes to the bug.
public enum Slug {
    /// Encode a string for a URL path segment.
    public static func encode(_ input: String) -> String {
        var out = ""
        for character in input {
            switch character {
            case "%": out += "%25"
            case " ": out += "%20"
            case "/": out += "%2F"
            default: out.append(character)
            }
        }
        return out
    }

    /// Decode a path segment produced by `encode`.
    ///
    /// PLANTED BUG: `%20` is never decoded, so any input containing a space fails the round trip.
    public static func decode(_ encoded: String) -> String {
        encoded
            .replacingOccurrences(of: "%2F", with: "/")
            .replacingOccurrences(of: "%25", with: "%")
    }
}
