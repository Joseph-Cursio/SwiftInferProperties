// Verify-ready corpus for the init-decode codec measured path.
//
// Three structs, each an instance-method encode + a decode initializer: one that
// round-trips correctly and two that break the law in distinct ways — a lossy
// encode (drops the sign) and an over-strict failable init (rejects its own
// encoder's output for negatives). Only execution tells them apart — every one
// reads like a codec.

/// Correct hex codec: `HexCode(hex: c.hex()) == c` for every Int.
struct HexCode: Equatable {
    var raw: Int
    init(raw: Int) { self.raw = raw }
    func hex() -> String { String(raw, radix: 16) }
    init?(hex string: String) {
        guard let value = Int(string, radix: 16) else { return nil }
        raw = value
    }
}

/// BUGGY — lossy encode: `encoded()` drops the sign, so a negative value decodes
/// to its magnitude. Caught by the mismatch check.
struct LossyCode: Equatable {
    var raw: Int
    init(raw: Int) { self.raw = raw }
    func encoded() -> String { String(abs(raw)) }
    init?(encoded string: String) {
        guard let value = Int(string) else { return nil }
        raw = value
    }
}

/// BUGGY — over-strict failable init: rejects negatives, but `serialized()`
/// happily emits them, so decoding a freshly-encoded negative returns nil.
/// Caught by the decode-nil check.
struct StrictCode: Equatable {
    var raw: Int
    init(raw: Int) { self.raw = raw }
    func serialized() -> String { String(raw) }
    init?(serialized string: String) {
        guard let value = Int(string), value >= 0 else { return nil }
        raw = value
    }
}
