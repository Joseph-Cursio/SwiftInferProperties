/// Marker distinguishing an **exhaustive** initializer from its ergonomic,
/// defaulted sibling.
///
/// ## Why this exists
///
/// A converter that rebuilds a value field-by-field — `updated(from:)`,
/// `init(from kitShape:)` — through an initializer with defaults will *silently
/// drop* any field it forgets. It compiles. The field simply reverts to its
/// default on the next round trip, and nothing anywhere reports it.
///
/// This repo has now been bitten by that four times, and every time the symptom
/// appeared several layers downstream as something other than a defect:
/// `IndexedTypeShape.enumCases` was absent for the type's whole life and
/// surfaced as a *hung verifier*, an `unsupported-carrier`, and an
/// `architectural-coverage-pending` — three shapes, all reading as limitations.
/// The archived note on `InteractionInvariantSuggestion.with(…)` had already
/// written the mechanism down: *"a single site that still rebuilds
/// field-by-field still drops any field it forgets, silently, because the
/// initialiser's parameters have defaults."*
///
/// Tests can only catch the fields someone thought to name.
/// `FieldCoverageReflectionTests` closes the encode side automatically via
/// `Mirror`, but reflection cannot see a field that encodes correctly and is
/// dropped by a *converter* — which is exactly where `enumCases` died.
///
/// ## What it does
///
/// A type with converters declares two initializers: the ergonomic one, whose
/// defaults keep ~90 test call sites readable, and an **exhaustive** one taking
/// this marker, in which *no parameter has a default*. Converters use the
/// exhaustive one.
///
/// Adding a stored property then plays out like this:
///
///   1. The compiler rejects the type — the property is uninitialised.
///   2. You add it to the ergonomic initializer, with a default. Fine.
///   3. You add it to the exhaustive initializer, **without** a default.
///   4. **Every converter now fails to compile** with a missing argument.
///
/// Step 4 is the point. The author is forced to answer the question the default
/// was silently answering for them: on a refresh, does this column come from the
/// existing record or the fresh one? A build that cannot succeed beats a test
/// that must be remembered.
///
/// See `docs/roadtest-self-dogfood.md` §11.3.4.
public enum EveryColumn: Sendable {
    /// The only case. Reads at the call site as
    /// `SemanticIndexEntry(everyColumn: .required, identityHash: …)`.
    case required
}
