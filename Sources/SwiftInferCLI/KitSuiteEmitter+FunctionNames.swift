extension KitSuiteEmitter {
    /// `VerifyHarness.LookupResult` + `Equatable` → `verifyHarnessLookupResultEquatable`.
    /// Nested types are the common case here and a dot is not legal in an identifier.
    ///
    /// Not injective: `Diagram.Node` and `DiagramNode` give one name. `emit` therefore issues
    /// the final name through a `FunctionNameTable`, and nothing may use this alone to name a
    /// declaration in the emitted suite (#715).
    static func functionName(_ typeName: String, _ conformance: String) -> String {
        let parts = typeName.split(separator: ".").map(String.init)
        let head = parts.first.map { $0.prefix(1).lowercased() + $0.dropFirst() } ?? ""
        let tail = parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return head + tail.joined() + conformance
    }

    /// **One emitted suite's test-function names (#715).** Every live block goes into ONE
    /// `@Suite` struct, so its functions share a scope, and `functionName` drops the dot:
    /// `extension Diagram.Node: Equatable {}` beside a type `DiagramNode` gave two
    /// `func diagramNodeEquatable()`, and the scaffolded file did not compile.
    ///
    /// The first request for a spelling gets it unchanged, so a suite with no collision is
    /// byte-for-byte what it was. Each later request gets the first free `_2`, `_3`, …. A suffixed
    /// spelling is itself recorded, so a carrier whose plain name happens to end in `_2` cannot take
    /// it twice. `emit` asks in its sorted carrier order, which makes the assignment deterministic.
    struct FunctionNameTable {
        private var issued: Set<String> = []

        mutating func issue(_ base: String) -> String {
            var name = base
            var suffix = 2
            while !issued.insert(name).inserted {
                name = "\(base)_\(suffix)"
                suffix += 1
            }
            return name
        }
    }
}
