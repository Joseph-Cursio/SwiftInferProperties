import Foundation

/// V1.47.D — curated resolver from generic associated-type carrier
/// names (e.g. `"Base.Index"`) to canonical concrete bindings (e.g.
/// `"Int"`, the `Index` of `Array<Int>`). The verify pipeline calls
/// `resolve(_:)` *before* consulting the `DerivationStrategist` — if a
/// match exists, the strategist sees the bound concrete carrier
/// (which it knows how to derive a generator for) instead of the
/// unbound associated type (which it can't).
///
/// **Why curated, not derived.** A general algorithm for binding
/// generic parameters would need to traverse the kit's `TypeShape`
/// graph and instantiate placeholder types — substantial scope. The
/// curated table covers the cycle-27 surface (`ChunkedByCollection`'s
/// `Base.Index`, plus the closely-related `Self.Index` /
/// `Iterator.Element` shapes) and acts as a baseline; cycle-44+ can
/// expand by adding entries when measurement evidence calls for it.
///
/// **Canonical binding choice.** The five initial entries all
/// instantiate `Base` (or `Self`) as `Array<Int>` for cycle-27
/// alignment — `Array<Int>.Index == Int`, the simplest non-trivial
/// `Comparable` index. Risk #3 of the v1.47 plan acknowledges this
/// bias; if cycle-44 surfaces a chunked-collection bug that only
/// reproduces for `String.Index` or `Set<Int>.Index`, the binding
/// would expand to a polymorphic-instantiation set.
public enum GenericBindingResolver {

    /// Curated bindings — keyed by the carrier name as it appears in
    /// `SemanticIndexEntry.typeName`. Values are the bound concrete
    /// carrier name the `DerivationStrategist` (or the v1.46 hardcoded
    /// path) consumes.
    public static let curatedBindings: [String: String] = [
        // `ChunkedByCollection<Base>.Index` and `Base.Index` carriers
        // bind `Base = Array<Int>`, so `Base.Index == Int`.
        "Base.Index": "Int",
        // Same binding for the element type — `Array<Int>.Element == Int`.
        "Base.Element": "Int",
        // The `Self.Index` / `Self.Element` shape that protocol
        // extensions on Collection / Sequence produce. Same canonical
        // binding for cycle-27 alignment.
        "Self.Index": "Int",
        "Self.Element": "Int",
        // IteratorProtocol's `Element` associated type. Iterator
        // instances rarely escape, but lifted suggestions reference
        // them by name.
        "Iterator.Element": "Int",
        // V1.51.A — bare→qualified canonicalization. The
        // discover/index path strips generic argument lists from
        // declarations (`struct Complex<RealType>` → `"Complex"`); the
        // v1.49 emitter expects the qualified form. V1.51.A maps the
        // bare form to the v1.46 hardcoded path's expected
        // `Complex<Double>` carrier. Bare→`<Float>` and `<Float80>`
        // variants stay unsupported in v1.51 (no v1.46 hardcoded path).
        "Complex": "Complex<Double>",
        // V1.58.A — first OC carrier binding. `OrderedSet` →
        // `OrderedSet<Int>`. Mirrors the V1.51.A pattern: cycle-27's
        // discover layer captured `typeName: "OrderedSet"` (no generic
        // arg); v1.58's emitter expects the bound form. Int is the
        // canonical Element type for the cycle-27 alignment (same
        // reason V1.47.D bound Base.Index → Int).
        //
        // **Scope**: cycle-55 measures whether this binding alone
        // unblocks resolution (carrier passes V1.47.F's `bound(_:)`
        // check); the downstream pipeline (strategist instance
        // generation + mutating-method emission for `sort()` etc.)
        // is v1.59+ work. Cycle-55 outcome for OS picks will likely
        // be `.measured-error` (build-failed at instance-method or
        // generator-recipe layer) — that's forward progress from
        // `.architectural-coverage-pending` and surfaces the next
        // gap layer for v1.59.
        "OrderedSet": "OrderedSet<Int>"
    ]

    /// Return the curated concrete carrier name bound to `carrier`,
    /// or `nil` if `carrier` isn't a known generic associated-type
    /// alias. Callers fall back to using `carrier` as-is when this
    /// returns nil.
    public static func resolve(_ carrier: String) -> String? {
        curatedBindings[carrier]
    }

    /// Return either the curated binding (if `carrier` is a known
    /// generic associated-type alias) or `carrier` itself. Convenience
    /// for call sites that want the "use bound if known, otherwise use
    /// as-is" behavior in one expression.
    public static func bound(_ carrier: String) -> String {
        resolve(carrier) ?? carrier
    }
}
