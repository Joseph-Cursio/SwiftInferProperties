/// How one drawn argument of a totality stub is sometimes taken from another, so that a relational
/// predicate's `true` side — a name equal to one inside a drawn node, two values that line up — is
/// reachable at all (#684 lever 2, `docs/plans/predicate-reach-at-source-scope.md` §2.4).
///
/// #665 measured 47 red relational `predicate` rows; read by hand, most need a drawn `String` to equal an
/// identifier inside a drawn syntax node, which two independent draws all but never produce.
///
/// Every argument is drawn first, exactly as without pairing, so the unpaired draws keep their place in
/// the random stream; each pairing then overwrites or extends its argument from the shared stream.
public enum DrawPairing: Equatable, Sendable {

    /// What a `String`-valued pairing writes into.
    public enum Target: Equatable, Sendable {
        /// The argument is replaced.
        case string
        /// The value is appended.
        case array
        /// The value is inserted.
        case set
    }

    /// Half the time, a name from argument `source`, a syntax-corpus node
    /// (`SwiftInferSyntaxCorpus.name(near:using:)`).
    case nameFrom(source: Int, target: Target)
    /// Half the time, argument `source`, a `String`, appended or inserted.
    case memberOf(source: Int, target: Target)
    /// One time in four, a copy of argument `source`, which has the same spelled type.
    case copyOf(source: Int)

    /// The pairing for each drawn argument that has one, by the first rule that applies (§2.4):
    /// `nameFrom` a syntax-corpus argument, then `memberOf` a `String` argument, then `copyOf` an
    /// earlier argument of the same spelled type.
    ///
    /// - Parameters:
    ///   - argumentTypes: each drawn argument's spelled type, in draw order.
    ///   - generators: each drawn argument's generator expression, in the same order.
    public static func plan(argumentTypes: [String], generators: [String]) -> [Int: Self] {
        guard argumentTypes.count == generators.count, argumentTypes.count > 1 else { return [:] }
        let types = argumentTypes.map(normalized)
        // ⚠ **Only a draw of the argument's own node type.** A composed draw — `gen(ExprSyntax.self)
        // .optional` for an `ExprSyntax?`, `.array(of:)` for a `[T]` — shares the prefix, and
        // `name(near:)` on an optional or an array does not compile.
        let nodes = generators.indices.filter { index in
            let spelled = argumentTypes[index].trimmingCharacters(in: .whitespaces)
            return generators[index].hasPrefix("\(syntaxCorpusDraw)\(spelled).self")
        }
        var plan: [Int: Self] = [:]
        for index in types.indices {
            let target = stringTarget(types[index])
            if let target, let source = nodes.first(where: { $0 != index }) {
                plan[index] = .nameFrom(source: source, target: target)
            } else if let target, target != .string,
                      let source = types.indices.first(where: { $0 != index && types[$0] == "String" }) {
                plan[index] = .memberOf(source: source, target: target)
            } else if let source = types.indices.first(where: { $0 < index && types[$0] == types[index] }) {
                plan[index] = .copyOf(source: source)
            }
        }
        return plan
    }

    /// The prefix of an unbiased or biased syntax-corpus draw.
    static let syntaxCorpusDraw = "SwiftInferSyntaxCorpus.gen("

    static func normalized(_ type: String) -> String {
        type.filter { !$0.isWhitespace }.replacingOccurrences(of: "Swift.", with: "")
    }

    static func stringTarget(_ type: String) -> Target? {
        switch type {
        case "String": return .string
        case "[String]": return .array
        case "Set<String>": return .set
        default: return nil
        }
    }

    /// The statement that applies this pairing to `arg<index>`, which the sample declared `var`.
    func statement(for index: Int) -> String {
        let argument = "arg\(index)"
        switch self {
        case let .nameFrom(source, target):
            return "if Bool.random(using: &rng), "
                + "let name = SwiftInferSyntaxCorpus.name(near: arg\(source), using: &rng) "
                + "{ \(Self.write("name", into: argument, target)) }"

        case let .memberOf(source, target):
            return "if Bool.random(using: &rng) { \(Self.write("arg\(source)", into: argument, target)) }"

        case let .copyOf(source):
            return "if Int.random(in: 0 ..< 4, using: &rng) == 0 { \(argument) = arg\(source) }"
        }
    }

    private static func write(_ value: String, into argument: String, _ target: Target) -> String {
        switch target {
        case .string: return "\(argument) = \(value)"
        case .array: return "\(argument).append(\(value))"
        case .set: return "\(argument).insert(\(value))"
        }
    }
}
