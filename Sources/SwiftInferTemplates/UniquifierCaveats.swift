import SwiftInferCore

/// "Why this might be wrong" for a `uniquifier` suggestion: the ways #669 and #692 found the law false or
/// out of reach on code that is correct.
enum UniquifierCaveats {
    static func caveats(for match: UniquifierMatch) -> [String] {
        var caveats = [
            "A FAILURE NEEDS A DRAWN NAME EQUAL TO ANOTHER PLUS \(spelling(match.shape.decoration)). A generator "
                + "drawing realistic names never collides, so the stub draws from a narrow alphabet on purpose: "
                + "`a`, `b`, each bare or decorated, and a dense run of 11 or more so a counter reaches 10.",
            "DISTINCT AS STRINGS, NOT UNDER THE CONSUMER'S EQUALITY. Where the names are compared after a "
                + "normalization (`lowercased()`, a sanitizer), the law owed is distinctness under it, and "
                + "exact-string distinctness is too weak.",
            "ITS DOMAIN MAY DEPEND ON HOW THE RECEIVER WAS BUILT. A receiver built over reserved names "
                + "(`init(reserving:)`) owes distinct results only over names drawn with that reservation in "
                + "mind; drawn independently, `A`, `A`, `A_1` can repeat `A_1` on correct code.",
        ]
        if match.shape.isMemoizing {
            caveats.insert(
                "MEMOIZING: the body returns the id it stored for a key it has seen, so the law is equal keys "
                    + "give equal ids and distinct keys give distinct ids, not n distinct results.",
                at: 0
            )
        }
        if let sentinel = match.shape.sentinel {
            caveats.append(
                "EVERY INPUT THE LEADING GUARD REJECTS GETS \(sentinel), by design, so the law leaves that "
                    + "result out."
            )
        }
        if match.nameParameter == nil {
            caveats.append(
                "THE NAME DOES NOT ENTER THROUGH ONE `String` PARAMETER, so the stub leaves a placeholder for "
                    + "building an argument whose name is the drawn one."
            )
        }
        return caveats
    }

    private static func spelling(_ decoration: UniquifierDecoration) -> String {
        switch decoration {
        case .counter(let prefix):
            prefix.isEmpty ? "A COUNTER" : "`\(prefix)` AND A COUNTER"

        case .appended(let text):
            "`\(text)`"
        }
    }
}
