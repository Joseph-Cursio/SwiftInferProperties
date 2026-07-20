import Foundation

/// Emits a standalone verifier for a codec round-trip whose **decode is an
/// initializer** — the measured half of Case 7 Part 2.
///
/// Given a carrier with an instance-method encode (`func base64EncodedString()
/// -> String`) and a decode initializer (`init?(base64Encoded: String)`), the
/// generated `main.swift` drives the directional round-trip law over a fixed set
/// of candidate values:
///
///   - **failable `init?`**: `Type(label: x.encode())` must SUCCEED and equal `x`
///     — i.e. `decode(encode(x)) == .some(x)`. A `nil` for a freshly-encoded
///     value is a failure (the decode rejects its own encoder's output); a
///     non-`nil` mismatch is a lossy encode.
///   - **non-failable `init`**: `Type(label: x.encode()) == x`.
///
/// The carrier is co-compiled into the verifier target (direct source
/// inclusion), so the stub constructs and calls it in-module — no import beyond
/// `Foundation` plus any `extraImports`. Deterministic (fixed candidate literals,
/// no RNG). Emits the same `VERIFY_*` marker contract as the algebraic /
/// ViewModel / reorder-partition stubs (`exit(1)` on FAIL) so `VerifyResultParser`
/// consumes it unchanged.
public enum InitDecodeStubEmitter {

    public struct Inputs: Equatable, Sendable {
        /// The carrier type (`Blob`).
        public let typeName: String
        /// The instance-method encode (`base64EncodedString`), returning the
        /// encoded representation.
        public let encodeMethod: String
        /// `true` when the encode is a computed property (`x.base64`) rather than
        /// a method (`x.base64EncodedString()`).
        public let encodeIsProperty: Bool
        /// The decode initializer's argument label (`base64Encoded`).
        public let decodeLabel: String
        /// `true` when the decode is a failable `init?` (returns `Self?`).
        public let isFailable: Bool
        /// A Swift expression of type `[typeName]` — the candidate values to
        /// round-trip (constructed via a memberwise / public init).
        public let valuesExpression: String
        /// Modules to import beyond `Foundation`.
        public let extraImports: [String]

        public init(
            typeName: String,
            encodeMethod: String,
            encodeIsProperty: Bool = false,
            decodeLabel: String,
            isFailable: Bool,
            valuesExpression: String,
            extraImports: [String] = []
        ) {
            self.typeName = typeName
            self.encodeMethod = encodeMethod
            self.encodeIsProperty = encodeIsProperty
            self.decodeLabel = decodeLabel
            self.isFailable = isFailable
            self.valuesExpression = valuesExpression
            self.extraImports = extraImports
        }
    }

    public static func emit(_ inputs: Inputs) -> String {
        let imports = (["Foundation"] + inputs.extraImports)
            .map { "import \($0)" }
            .joined(separator: "\n")
        return """
        // Auto-generated init-decode codec verifier.
        // Codec: \(inputs.typeName).\(encodeCall(inputs, receiver: "x")) <-> \
        \(inputs.typeName)(\(inputs.decodeLabel):)\(inputs.isFailable ? " (failable)" : "")
        \(imports)

        func runInitDecodeCheck() -> (pass: Bool, detail: String) {
            let candidates: [\(inputs.typeName)] = \(inputs.valuesExpression)
            for original in candidates {
                let encoded = \(encodeCall(inputs, receiver: "original"))
        \(decodeBlock(inputs))
            }
            return (true, "")
        }

        let outcome = runInitDecodeCheck()
        if outcome.pass {
            print("VERIFY_DEFAULT_RESULT: PASS")
            print("VERIFY_DEFAULT_TRIALS: 1")
            print("VERIFY_EDGE_RESULT: PASS")
            print("VERIFY_EDGE_TRIALS: 0")
            print("VERIFY_EDGE_SAMPLED: 0")
            exit(0)
        } else {
            print("VERIFY_DEFAULT_RESULT: FAIL")
            print("VERIFY_DEFAULT_TRIAL: 0")
            print("VERIFY_DEFAULT_DETAIL: \\(outcome.detail)")
            exit(1)
        }
        """
    }

    /// `original.base64EncodedString()` (method) or `original.base64` (property).
    private static func encodeCall(_ inputs: Inputs, receiver: String) -> String {
        inputs.encodeIsProperty
            ? "\(receiver).\(inputs.encodeMethod)"
            : "\(receiver).\(inputs.encodeMethod)()"
    }

    private static func decodeBlock(_ inputs: Inputs) -> String {
        if inputs.isFailable {
            return """
                    guard let decoded = \(inputs.typeName)(\(inputs.decodeLabel): encoded) else {
                        return (false, "failable decode returned nil for a freshly-encoded value: \\(encoded)")
                    }
                    if decoded != original {
                        return (false, "round-trip mismatch: in=\\(original) encoded=\\(encoded) out=\\(decoded)")
                    }
            """
        }
        return """
                let decoded = \(inputs.typeName)(\(inputs.decodeLabel): encoded)
                if decoded != original {
                    return (false, "round-trip mismatch: in=\\(original) encoded=\\(encoded) out=\\(decoded)")
                }
        """
    }
}
