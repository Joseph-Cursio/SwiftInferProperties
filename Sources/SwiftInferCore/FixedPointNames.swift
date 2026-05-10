/// V1.22.C — curated set of function names that signal "transform input
/// into a canonical form whose application is idempotent." Three-cycle
/// carry-forward priority (cycles 15/16/17/18) addressing the recall
/// gap on lower-confidence idempotence names that aren't in
/// `IdempotenceTemplate.curatedVerbs` (the V1.4.1 `+40` set).
///
/// **First recall-positive signal in the post-V1.4.3 era.** All prior
/// cycles (V1.4.3 onward) shipped suppression-only mechanisms; V1.22.C
/// is the first cycle to introduce a positive signal class.
///
/// **Why a separate set vs extending `IdempotenceTemplate.curatedVerbs`.**
/// The V1.4.1 curated-verb list earns `+40` because those names are
/// high-confidence idempotence indicators (`normalize`, `canonicalize`,
/// `flatten`, etc.). Fixed-point names like `clamp` / `truncate` /
/// `simplify` are lower-confidence — `clamp` can be parameterized
/// non-idempotently (`clamp(value, to: rangeA)` then `clamp(value, to: rangeB)`
/// yields a different result). The smaller `+10` magnitude reflects this
/// lower confidence per the v1.22 plan §"Open decisions" #1 lean.
///
/// **Excludes overlaps with `curatedVerbs`.** Names like `normalize`,
/// `canonicalize`, `flatten`, `sanitize` are already in `curatedVerbs`
/// at `+40`. Including them here at `+10` would be redundant (already
/// Strong-tier; the additional `+10` doesn't change the tier
/// classification). The set focuses on names that aren't already
/// covered by the V1.4.1 list.
public enum FixedPointNames {

    /// Curated fixed-point function names (NOT overlapping with
    /// `IdempotenceTemplate.curatedVerbs`). Each name signals
    /// "transform input into a canonical form" with idempotence as a
    /// likely (but not by-construction-guaranteed) consequence:
    ///
    /// - `dedupe` — variant of `deduplicate` (which IS in curatedVerbs);
    ///   the shorter form is common in user code and project domains.
    /// - `simplify` — algebraic / structural simplification
    ///   (e.g., `Polynomial.simplified()` reducing to canonical form).
    /// - `clamp` — bounded value coercion (idempotent on the bounded
    ///   subdomain; non-idempotent if the bound parameter changes
    ///   between calls — but the typical signature `clamp(_: T) -> T`
    ///   is parameter-free post-curry, so idempotence holds).
    /// - `truncate` — string / numeric truncation to a target length
    ///   or precision; idempotent when the target is fixed.
    /// - `standardize` — variant of `normalize` (which IS in
    ///   curatedVerbs); included for naming-style coverage in domains
    ///   that prefer this verb.
    ///
    /// Project extension via the existing `Vocabulary.idempotenceVerbs`
    /// slot (no new vocabulary slot — project-specific fixed-point names
    /// belong alongside the project's idempotence verb list).
    public static let curated: Set<String> = [
        "dedupe",
        "simplify",
        "clamp",
        "truncate",
        "standardize"
    ]
}
