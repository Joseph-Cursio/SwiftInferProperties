/// Whether two carrier types are **the two halves of one codec** — a
/// `Loader`/`Writer`, `Encoder`/`Decoder`, `Parser`/`Printer` split.
///
/// ## What this is for
///
/// `RoundTripTemplate`'s cross-type counter subtracts 25 whenever a pair's
/// halves live in different containing types. That counter earns its keep: on
/// the corpora measured for `docs/measurements/parsing-catalog-gap.md` §3b it suppresses
/// **1,380 cross-type pairs**, and essentially all of them are noise — 1,310
/// have the degenerate `T -> T` shape (`index(after:)` on one collection
/// against `index(before:)` on another; every `Index -> Index` function pairs
/// with every other by type text alone), and most of the remaining 70 are
/// accidents like `ByteBufferAllocator.buffer(capacity: Int) -> ByteBuffer`
/// against `ByteBuffer.readerIndex: Int`.
///
/// But it also suppresses the one shape a serializer round trip **actually
/// takes**. In real code the parser and the printer are almost never in the
/// same type:
///
///     LintConfigurationLoader.load(from: String) -> LintConfiguration
///     LintConfigurationWriter.render(_: LintConfiguration) -> String
///
/// A package built around a config serializer therefore got no round-trip
/// proposal for it at any tier, while getting a spurious `String -> String`
/// pairing of two unrelated path helpers. The counter's stated reason —
/// *"property cannot type-check across distinct containing types"* — is a
/// code-generation concern, and for a codec split it is simply wrong: the
/// round trip is *designed* to span the two types, and the emitted test calls
/// one static method on each.
///
/// ## Why the role noun, and not the stem
///
/// The obvious discriminator is a shared stem — `LintConfiguration`Loader and
/// `LintConfiguration`Writer share one. Measurement killed that idea outright:
/// the top noise carriers on swift-collections are `BigString` against
/// `BigString.UTF8View`, `BigSubstring` against `BigSubstring.UTF16View`,
/// `BigString._Chunk` against `BigString` — 64 pairs on the worst single
/// combination, **all sharing a stem**. A stem test would have admitted the
/// entire flood the counter exists to stop.
///
/// A second candidate — "domain ≠ codomain, so it is a real transformation
/// rather than an `Index -> Index` coincidence" — was also measured and also
/// fails: it admits 70 pairs of which only two are codecs.
///
/// What separates the signal from the noise is that the two carriers name
/// **mutually inverse roles**. `Loader` and `Writer` are opposite jobs;
/// `BigString` and `BigSubstring.UTF8View` are two views of one thing, and
/// `ByteBufferAllocator` and `ByteBuffer` are a factory and its product.
/// Neither of the latter is a pair of inverse roles, and neither is admitted.
public enum CodecCarrierPairing {

    /// Role nouns that name **opposite halves of one codec**, lowercased.
    ///
    /// Both spellings of the agent suffix are listed where Swift and its
    /// neighbours disagree (`marshaller`/`marshaler`, `encryptor`/`encrypter`)
    /// — a missing spelling fails silently, which is the failure mode this
    /// whole document is about.
    ///
    /// `persistence` is deliberately absent, and it costs a real pair:
    /// SwiftProjectLint's `YAMLConfigurationPersistence.load` ×
    /// `LintConfigurationWriter.render` stays suppressed. "Persistence" names
    /// a *concern*, not a direction — a `FooPersistence` is as likely to hold
    /// both halves as one — so admitting it would admit any type whose name
    /// ends that way against any other. Recorded rather than quietly widened.
    public static let inverseRoleNouns: [(String, String)] = [
        ("encoder", "decoder"),
        ("serializer", "deserializer"),
        ("reader", "writer"),
        ("loader", "writer"),
        ("loader", "saver"),
        ("loader", "dumper"),
        ("parser", "printer"),
        ("parser", "formatter"),
        ("parser", "renderer"),
        ("parser", "serializer"),
        ("parser", "writer"),
        ("marshaller", "unmarshaller"),
        ("marshaler", "unmarshaler"),
        ("compressor", "decompressor"),
        ("encryptor", "decryptor"),
        ("encrypter", "decrypter"),
        ("packer", "unpacker"),
        ("importer", "exporter")
    ]

    /// The trailing role noun of a carrier — the last camelCase token of its
    /// last dotted component. `LintConfigurationLoader` → `loader`;
    /// `BigSubstring.UTF8View` → `view`.
    public static func roleNoun(of carrierName: String) -> String? {
        let leaf = carrierName.split(separator: ".").last.map(String.init) ?? carrierName
        return StreamConsumption.camelCaseTokens(leaf).last
    }

    /// Whether `lhs` and `rhs` name mutually inverse codec roles.
    ///
    /// Order-insensitive: a pair is the same pair whichever half
    /// `FunctionPairing` happened to orient forward.
    public static func areComplementary(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = roleNoun(of: lhs), let right = roleNoun(of: rhs),
              left != right else {
            return false
        }
        return inverseRoleNouns.contains { pair in
            (pair.0 == left && pair.1 == right) || (pair.0 == right && pair.1 == left)
        }
    }
}
