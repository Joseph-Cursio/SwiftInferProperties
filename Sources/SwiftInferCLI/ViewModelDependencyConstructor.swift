import Foundation
import SwiftInferCore

/// PROTOTYPE — resolves how to *construct* a view model for verify,
/// synthesizing no-op fakes for its injected protocol dependencies. A
/// zero-arg view model constructs as `Type()`; a dependency-injected one
/// constructs as `Type(label: Fake_P(), other: nil, …)` with the fake
/// `struct`s emitted as a preamble. Returns `nil` (gated) when any init
/// parameter can't be satisfied — a non-fakeable protocol (a property /
/// non-`Void`-method requirement) or a non-defaultable concrete type.
///
/// **Scope (this slice):** init parameters that are (a) a fakeable
/// protocol (`ViewModelProtocolScanner` — Void-method-only), (b) an
/// Optional (→ `nil`), or (c) a curated defaultable scalar. Unlocks the
/// common "VM injects a storage/service protocol" shape; the real app's
/// VMs with richer dependency graphs stay gated.
public enum ViewModelDependencyConstructor {

    public struct Construction: Equatable {
        /// Fake `struct` definitions to emit before the verifier function
        /// (empty for a zero-arg view model).
        public let preamble: String
        /// The construction expression (`SelectionModel()` /
        /// `LibraryModel(store: Fake_Store())`).
        public let expression: String

        public init(preamble: String, expression: String) {
            self.preamble = preamble
            self.expression = expression
        }
    }

    public static func resolve(
        _ candidate: ViewModelCandidate,
        protocols: [ViewModelProtocolScanner.ProtocolDecl]
    ) -> Construction? {
        if candidate.isZeroArgConstructible {
            return Construction(preamble: "", expression: "\(candidate.typeName)()")
        }
        // Pre-synthesize a fake for every fakeable protocol, keyed by name.
        var fakeable: [String: String] = [:]
        for proto in protocols where fakeable[proto.name] == nil {
            if let source = ViewModelProtocolFaker.fakeStruct(for: proto) {
                fakeable[proto.name] = source
            }
        }
        var args: [String] = []
        var fakeSources: [String: String] = [:]
        for parameter in candidate.initParameters {
            guard let value = satisfy(parameter, fakeable: fakeable, fakeSources: &fakeSources) else {
                return nil
            }
            args.append(parameter.label.map { "\($0): \(value)" } ?? value)
        }
        let preamble = fakeSources.keys.sorted().compactMap { fakeSources[$0] }.joined(separator: "\n\n")
        return Construction(
            preamble: preamble,
            expression: "\(candidate.typeName)(\(args.joined(separator: ", ")))"
        )
    }

    /// Produce the argument expression for one init parameter, recording
    /// any fake `struct` it needs. `nil` when the parameter can't be
    /// satisfied (gates construction).
    private static func satisfy(
        _ parameter: ViewModelInitParameter,
        fakeable: [String: String],
        fakeSources: inout [String: String]
    ) -> String? {
        let type = parameter.typeText.trimmingCharacters(in: .whitespaces)
        if type.hasSuffix("?") {
            return "nil"   // Optional dependency → nil
        }
        let bareType = type.hasPrefix("any ")
            ? String(type.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            : type
        if let fakeSource = fakeable[bareType] {
            fakeSources[bareType] = fakeSource
            return "Fake_\(bareType)()"
        }
        return ViewModelDefaultValue.value(for: bareType)
    }
}
