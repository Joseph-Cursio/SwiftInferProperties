@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// **The drift guard the catalog's own doc claimed it already had.**
///
/// `CuratedEntryRole`'s doc says the role "is DERIVED from `template`, so it cannot drift:
/// the day a shape gets a template, its entries stop being reference and start anchoring."
/// The derivation is real — `law()` computes `role` from `template` — so *that* cannot
/// drift. But the **tagging** is a hand-written argument, and nothing checked it against
/// the set of templates that actually exist.
///
/// It drifted badly. On 2026-08-01, 48 of 71 laws were `.reference`; **34 of those 48 named
/// a law a shipped template already states**. `Array`'s "count is additive over
/// concatenation" carried `template: "homomorphism"` while `Deque`'s *identical* law
/// carried nothing — which is what makes it an oversight rather than a policy.
///
/// The cost is not cosmetic in either direction:
///
/// - `StdlibAnchor` keys on `entry.template == candidate.templateName`, so an untagged row
///   is invisible to `discover`. The `Stack` / `Queue` rows say in their own comment that
///   they exist "so the stdlib anchor has a ground truth to match a discovered `push`/`pop`
///   pair against" — and they could not, for want of a tag.
/// - The `.reference` count is the **catalog backlog metric**. Reporting 48 when the true
///   figure was 14 overstates the gap by more than 3x, and points work at rows that were
///   already covered.
///
/// So this suite pins the reference set explicitly. A new law with no template, or a newly
/// tagged row, fails here until someone states which case it is.
@Suite("Catalog template tags — the reference set is explicit, not residual")
struct CatalogTemplateTagDriftTests {

    /// Every law that deliberately anchors nothing, with the reason it cannot.
    ///
    /// Keyed by `(type, structure)`. **Adding a row here is a claim that no shipped template
    /// states this law** — check `TemplatePack.allTemplateNames` before believing it.
    static let deliberateReferenceLaws: [String: String] = [
        // Naming a template here would be actively WRONG, not merely absent.
        "OrderedSet|commutative under membership (NOT under order)":
            "Tagging `commutativity` would tell a reader that OrderedSet.union is "
            + "commutative. It is not, under `==` — it keeps the LEFT operand's order. The "
            + "row states the COARSER membership equality only, and the anchor prints the "
            + "statement without that distinction. A harmful tag, not a missing one.",

        // Real shapes, no template names them.
        "OrderedSet|union preserves left order":
            "Order-preservation of a binary op has no template. Related to "
            + "`OrderedCarrierDiscriminator`, which decides whether order is part of a "
            + "carrier's value — but no template states this law.",
        "Set|distributive lattice":
            "Three-operand lattice law; no template. Kit-side `SetAlgebra` covers it.",
        "Set|absorption":
            "Two-operand absorption; no template. Kit-side `SetAlgebra` covers it.",
        "BitSet|absorption":
            "Same shape as the `Set` row above.",
        "Set|De Morgan (relative form)":
            "No template. The note records why the relative form is the statable one: "
            + "SetAlgebra has no complement.",
        "Set|symmetricDifference self-inverse":
            "`involution` is UNARY — `f(f(x)) == x`. This is binary and parameterised by "
            + "the second operand: `a.symmetricDifference(b).symmetricDifference(b) == a`. "
            + "Closer to `inverse-pair`, but that wants two distinct named functions.",
        "TreeSet|value semantics — mutating a copy leaves the original untouched":
            "No template states value semantics. It needs a mutation and an aliasing "
            + "observation, which is a stateful shape rather than a value-semantic law.",
        "Algorithms.min|min(count:) agrees with the sorted prefix":
            "An oracle law against a sorted-array model. `model-law` abstracts via "
            + "`contains` (membership), so it does not state an ORDERED prefix agreement.",

        // Model laws whose abstraction function is not the one `model-law` uses.
        "Heap|popMin drains in sorted order (model-based)":
            "A model law, but `ModelLawTemplate`'s abstraction function is `contains`. This "
            + "drains to a sorted ARRAY, which is an ordered model. `Heap` is not even a "
            + "Sequence, so `sequence-view-model-law` does not reach it either.",
        "Heap|min / max agree with the model":
            "Same abstraction-function mismatch as the drain law above.",

        // The functor family: identity ships, composition does not.
        "Optional|functor composition":
            "`composition` is a DIFFERENT law — two sequential mutating additive-monoid "
            + "actions equal one combined call. Functor composition needs two GENERATED "
            + "FUNCTIONS, a generator capability rather than a template shape. See "
            + "`FunctorIdentityTemplate`'s 'IDENTITY IS THE WEAKER HALF' caveat.",
        "Dictionary|mapValues functor composition":
            "Same as the `Optional` row above.",
        "Optional|monad right identity":
            "`flatMap` monad laws have no template. Identity ships; the monad laws need "
            + "a generated function returning the carrier."
    ]

    private static func key(_ entry: CuratedEntry) -> String { "\(entry.type)|\(entry.structure)" }

    @Test("Every reference law is on the allowlist with a stated reason")
    func referenceLawsAreDeliberate() {
        let reference = CuratedStdlibCatalog.laws.filter { $0.role == .reference }
        for entry in reference {
            #expect(
                Self.deliberateReferenceLaws[Self.key(entry)] != nil,
                """
                `\(Self.key(entry))` anchors nothing and is not on the allowlist.
                Either tag it with the template that states it, or add it to \
                `deliberateReferenceLaws` saying which template SHOULD have covered it and \
                why it does not. Check `TemplatePack.allTemplateNames` first — this suite \
                exists because 34 rows sat untagged while their templates shipped.
                """
            )
        }
    }

    @Test("The allowlist has no stale entries")
    func allowlistHasNoStaleEntries() {
        let referenceKeys = Set(
            CuratedStdlibCatalog.laws.filter { $0.role == .reference }.map(Self.key)
        )
        for listed in Self.deliberateReferenceLaws.keys {
            #expect(
                referenceKeys.contains(listed),
                Comment(rawValue: "`\(listed)` is on the reference allowlist but now "
                    + "anchors (or was removed). Delete its allowlist entry.")
            )
        }
    }

    /// The headline number, pinned. Not a style assertion — it is the catalog backlog
    /// metric, and it was over-reported by more than 3x for as long as nothing watched it.
    @Test("Reference laws stay a small, named minority")
    func referenceCountIsPinned() {
        let reference = CuratedStdlibCatalog.laws.filter { $0.role == .reference }
        #expect(reference.count == Self.deliberateReferenceLaws.count)
        #expect(reference.count == 14, "was 48 before the 2026-08-01 re-tag")
    }

    /// The exact template names the catalog tags with.
    ///
    /// **This is pinned by hand because no runtime registry of emitted template names
    /// exists**, which is a large part of why the tag drift went unseen. The two candidate
    /// oracles both under-report:
    ///
    /// - `TemplatePack.allTemplateNames` resolves to **10** names — packs are a `--packs`
    ///   filter, not a registry, and it omits `involution` and `homomorphism`, which the
    ///   catalog has tagged since long before this sweep.
    /// - `TemplateName` has **17** cases against ~89 template files (`docs/design-internal/glossary.md`
    ///   says so outright: it "does not enumerate every template discovery emits").
    ///
    /// So the guard here is narrower but real: a **typo** in a tag silently never fires,
    /// and changing this set is the thing that catches it.
    static let tagsInUse: Set<String> = [
        "associativity", "binary-idempotence", "commutativity", "ended-access-round-trip",
        "functor-identity", "homomorphism", "idempotence", "identity-element",
        "involution", "multiplicative-homomorphism", "round-trip"
    ]

    @Test("Tags are drawn from a pinned set — a typo would never fire")
    func tagsAreFromThePinnedSet() {
        let used = Set(CuratedStdlibCatalog.all.compactMap(\.template))
        #expect(used == Self.tagsInUse)
    }

    /// The regression that motivated the sweep: two carriers, one law, one tag.
    @Test("Identical laws on different carriers carry the same tag")
    func identicalLawsAgree() {
        let additive = CuratedStdlibCatalog.laws.filter {
            $0.statement == "(a + b).count == a.count + b.count"
        }
        #expect(additive.count == 2, "Array and Deque")
        #expect(Set(additive.map(\.template)) == ["homomorphism"])

        let functorIdentity = CuratedStdlibCatalog.laws.filter {
            $0.structure.contains("functor identity")
        }
        #expect(functorIdentity.count == 4, "Optional, Dictionary, OrderedDictionary, TreeDictionary")
        #expect(Set(functorIdentity.map(\.template)) == ["functor-identity"])
    }
}
