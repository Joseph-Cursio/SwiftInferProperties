import Foundation

/// Canonicalises a **module-qualified stdlib spelling** — `Swift.String` → `String` — at the one
/// seam where a scanned type name crosses into the kit.
///
/// ## The defect
///
/// `RawType(typeName:)` matches its cases **exactly**: `"String"`, `"Int"`, `"Bool"`. Nothing
/// anywhere in the kit strips a module qualifier, so `Swift.String` resolves to no generator, a
/// member typed with it makes its whole enclosing type underivable, and the row lands as
/// `unsupported-carrier` — a label that says *the carrier is exotic* about a `String`.
///
/// This scanner records what the source says, and hand-written Swift almost never writes
/// `Swift.String`. **Generated code does, everywhere.** `swift-openapi-generator` fully-qualifies
/// every type it emits, and that is a large class of real Swift the toolchain will keep meeting.
///
/// ## What it is worth, stated honestly in both directions
///
/// **On `MacPaw/OpenAI` @ `a532be8` the A/B is 0 → 16 of 28** `codable-round-trip` rows whose
/// member tree becomes fully resolvable. Every one of those 28 was blocked, and none was blocked
/// by the thing that looked like the culprit — the recursion into custom field types already
/// works (`GeneratorResolver`, `StrategistDispatchEmitter+Recursion`). The binding constraint was
/// leaf recognition.
///
/// **Across the 20 resolving manifest corpora the population is ONE occurrence.** This moves no
/// census and no corpus figure, and a reader who quotes the 16 without the 1 is quoting a number
/// about generated code as though it were a number about Swift. The manifest contains no
/// generated-code subject, so it cannot answer how common this is — the fourth time *a census is
/// only as wide as its corpus list* has been paid for here.
///
/// ## Why this is a correctness fix and not a threshold
///
/// The standing rule is *raise thresholds, don't pile on filters*, and the Daikon trap is about
/// buying recall with precision. This buys neither: `Swift.String` **is** `String`, and treating
/// it as an unknown type is simply wrong. No suggestion becomes weaker, and nothing is admitted
/// that was not already admissible under its own spelling.
///
/// ## Why it strips a NAMED prefix rather than the last component
///
/// Taking the last dotted component would map a user's `MyModule.String` — or
/// `Components.Schemas.Response` — onto a stdlib name it is not. Only `Swift.` and `Foundation.`
/// are stripped, and only when the remainder is a name the kit actually generates for. An unknown
/// remainder is left exactly as written, so a qualified custom type still reaches the resolver
/// under its own key.
public enum StdlibTypeSpelling {

    /// The leaf names the kit generates for: `RawType.allCases` plus the Foundation leaves
    /// `CompositeMemberParser` recognises.
    ///
    /// **Duplicated from the kit deliberately, and it is the narrow direction.** A name missing
    /// here is left qualified and stays underivable — today's behaviour. A name wrongly added
    /// would rewrite a spelling the kit cannot generate for, which changes a `.todo` reason into
    /// a different `.todo` reason and nothing else. The failure mode of drift is inertness, not
    /// unsoundness, which is why this does not need a cross-repo contract test.
    static let generatableLeaves: Set<String> = [
        "Int", "String", "Bool", "Double", "Float",
        "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Date", "UUID", "Data", "URL", "Decimal"
    ]

    /// Module qualifiers safe to drop. Neither can name a user module in practice, and both are
    /// what a code generator writes.
    static let strippableModules: Set<String> = ["Swift", "Foundation"]

    /// `"[String: Swift.String]"` → `"[String: String]"`; `"Components.Schemas.Response"`
    /// unchanged.
    ///
    /// Rewrites **every** occurrence rather than only a leading one, because the spellings that
    /// matter are composed: `[Swift.String]`, `Swift.String?`, `[Swift.String: Swift.Int]`. The
    /// scan is over identifier runs, so a match can only ever replace a whole `Module.Name` pair.
    public static func canonical(_ typeName: String) -> String {
        guard typeName.contains(".") else { return typeName }
        var result = ""
        var token = ""
        for character in typeName {
            if character.isLetter || character.isNumber || character == "_" || character == "." {
                token.append(character)
            } else {
                result += canonicalToken(token)
                token = ""
                result.append(character)
            }
        }
        return result + canonicalToken(token)
    }

    /// One dotted identifier run, rewritten only on an exact `<strippable>.<generatable>` match.
    private static func canonicalToken(_ token: String) -> String {
        guard !token.isEmpty else { return token }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              strippableModules.contains(String(parts[0])),
              generatableLeaves.contains(String(parts[1]))
        else { return token }
        return String(parts[1])
    }
}
