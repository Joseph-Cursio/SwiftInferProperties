/// The genuinely non-idempotent layer.
///
/// SwiftIdempotency defines `@NonIdempotent` as "unconditionally
/// non-idempotent — re-invocation produces additional observable effects
/// (sending email, inserting rows, publishing events)". These are those three,
/// literally, so the annotations are true by construction rather than by
/// argument.
public enum Effects {

    /// Re-invocation sends a second email. Nothing dedupes it.
    ///
    /// @lint.effect non_idempotent
    public static func sendReceipt(_ address: String) -> String {
        Transport.deliver(to: address)
        return address
    }

    /// Re-invocation inserts a second row — the table has no unique constraint
    /// on the payload, which is exactly what makes this tier apply.
    ///
    /// @lint.effect non_idempotent
    public static func insertAuditRow(_ payload: String) -> String {
        Transport.append(payload)
        return payload
    }
}

/// Stands in for the outside world so the fixture stays dependency-free and
/// runs anywhere. The `Transport` calls are what the tiers above are about.
enum Transport {
    static func deliver(to address: String) { _ = address }
    static func append(_ row: String) { _ = row }
}
