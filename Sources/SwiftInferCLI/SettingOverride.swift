import ArgumentParser

/// `--include-possible` / `--no-include-possible`: show or hide the below-cut `Possible` tier.
public enum IncludePossibleFlag: String, EnumerableFlag {
    /// `--include-possible`.
    case includePossible
    /// `--no-include-possible`.
    case noIncludePossible
}

/// `--docstring-advice` / `--no-docstring-advice`: print or suppress the documented-contract advice.
public enum DocstringAdviceFlag: String, EnumerableFlag {
    /// `--docstring-advice`.
    case docstringAdvice
    /// `--no-docstring-advice`.
    case noDocstringAdvice
}

/// `--emit-regression` / `--no-emit-regression`: write a regression test from a counterexample, or don't.
public enum EmitRegressionFlag: String, EnumerableFlag {
    /// `--emit-regression`.
    case emitRegression
    /// `--no-emit-regression`.
    case noEmitRegression
}

/// What a `--name` / `--no-name` flag pair said on the command line: turn a setting on, turn it
/// off, or nothing at all, which leaves the config file or the command's own default to decide.
///
/// A named type rather than `Bool?`, so the third state reads as what it means at every use
/// site. A Boolean literal is an explicit override, so `includePossible: true` still reads as
/// one in calls and tests.
public enum SettingOverride: Sendable, Equatable, ExpressibleByBooleanLiteral {
    /// Neither flag was passed: the config file, or failing that the default, decides.
    case notGiven
    /// `--name` was passed.
    case enabled
    /// `--no-name` was passed.
    case disabled

    /// An explicit override: `.enabled` for `true`, `.disabled` for `false`.
    public init(_ value: Bool) {
        self = value ? .enabled : .disabled
    }

    /// `true` is `.enabled` and `false` is `.disabled`.
    public init(booleanLiteral value: Bool) {
        self.init(value)
    }

    /// Reads a parsed flag pair, where `enabling` is the case that turns the setting on and an
    /// absent flag is `.notGiven`.
    public init<Flag: Equatable>(_ flag: Flag?, enabledBy enabling: Flag) {
        switch flag {
        case nil: self = .notGiven
        case enabling: self = .enabled
        default: self = .disabled
        }
    }

    /// The setting's value: this override when one was given, otherwise `fallback`.
    public func resolved(otherwise fallback: Bool) -> Bool {
        switch self {
        case .notGiven: fallback
        case .enabled: true
        case .disabled: false
        }
    }
}
