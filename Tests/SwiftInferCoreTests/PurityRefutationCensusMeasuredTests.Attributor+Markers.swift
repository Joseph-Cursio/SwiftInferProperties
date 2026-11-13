import SwiftEffectInference
import SwiftSyntax

@testable import SwiftInferCore

// MARK: - The token rules, re-derived

/// `PurityInferrer`'s marker sets and its token rules (`PurityInferrer+Markers.swift`), re-derived because they are
/// `private` there. Moved out of `+Support.swift` at the SEI `ba3624d` bump, which took that file past its length cap.
///
/// **What `ba3624d` added** over `5fbee6f`, the pin before it (`ba3624d` merges #35's `cc5b126`; the trees are equal):
/// - 35 system-effect markers, from `NSWorkspace` to the `sqlite3_*` entry points (SEI #35);
/// - SEI #31's readers of ambient time and settings, each one position-sensitive:
///   - `isDateInToday` and its siblings;
///   - `timeIntervalSinceNow` and `autoupdatingCurrent`, which also count as key-path components;
///   - `.current` on `Calendar`, `NSCalendar` and `NSLocale`;
///   - the bare constructions `DateInterval()`, `NSDate()`, `NSUUID()`;
///   - `NSDate.now`, and a base-less `.now`;
///   - the time-zone members that read now by default;
///   - a `formatted(…)` that reads the ambient locale.
///
/// `verdictAgreesWithSoundPurity` caught the drift at the bump: `VerifierSubprocess.waitForExit` reads
/// `.now() + timeout`, which SEI #31's `c273160` refutes and the old replica did not.
extension PurityRefutationCensusMeasuredTests.Attributor {

    /// `PurityInferrer.sideEffectMarkers`.
    ///
    /// **`FileHandle` / `Process` / `Pipe` joined at SEI `3ea25f2`**, which
    /// closed the non-throwing half of the I/O hole: `throwsOnlyItsOwnErrors`
    /// only ever covered *throwing* functions, and
    /// `FileHandle.standardError.write(_:)` does not throw. `String` and
    /// `Data` are deliberately still absent — matched by bare identifier they
    /// would refute nearly everything.
    ///
    /// **The file-system read members joined at SEI `fff33cf`**, which closed
    /// the case the sentence above used to end with: `String(contentsOf:)`
    /// and `Data(contentsOf:)` throw, so the `try` gate was said to reach
    /// them — true only while the throw propagates, and `try?` swallows it.
    ///
    /// **`contentsOf` is deliberately not here, and must not be added.** SEI
    /// carried it as a bare token from `fff33cf` to `23d1dab`, where it also
    /// matched `append(contentsOf:)` and refuted every function that appends
    /// one collection to another — 43 of this corpus's functions. It is
    /// matched on the callee instead; see `CensusFileReadChecker`.
    ///
    /// **The system effects outside the process joined at SEI `cc5b126`** (#35), after a generated law over
    /// SwiftLintRuleStudio's `NSWorkspace.shared.open(url)` wrapper opened browser pages on every trial.
    static let sideEffectMarkers: Set<String> = [
        "print", "NSLog", "FileManager", "URLSession", "UserDefaults",
        "NotificationCenter", "DispatchQueue",
        "FileHandle", "Process", "Pipe",
        "resourceValues", "checkResourceIsReachable", "checkPromisedItemIsReachable",
        "startAccessingSecurityScopedResource", "stopAccessingSecurityScopedResource",
        "contentsOfFile", "contentsOfDirectory",
        "NSWorkspace", "NSApp", "activateFileViewerSelecting", "urlForApplication",
        "openURL", "LSOpenCFURLRef",
        "runModal", "UNUserNotificationCenter", "NSUserNotificationCenter",
        "AudioServicesPlaySystemSound", "NSBeep",
        "NSAppleScript", "NSUserAppleScriptTask", "NSUserUnixTask", "OSAScript",
        "posix_spawn", "execv", "AuthorizationCreate", "CFNotificationCenterPostNotification",
        "SecItemAdd", "SecItemUpdate", "SecItemDelete", "SecItemCopyMatching",
        "sqlite3_open", "sqlite3_open_v2", "sqlite3_exec", "sqlite3_prepare_v2", "sqlite3_step",
        "sqlite3_close", "sqlite3_close_v2", "sqlite3_finalize", "sqlite3_reset",
        "sqlite3_bind_text", "sqlite3_column_text", "sqlite3_errmsg",
    ]

    /// `PurityInferrer.nondeterministicMarkers`, which includes the property markers.
    static let nondeterministicMarkers: Set<String> = Set([
        "arc4random", "arc4random_uniform", "drand48", "CFAbsoluteTimeGetCurrent",
        "random", "randomElement", "shuffled",
        "Date", "UUID",
        "isDateInToday", "isDateInYesterday", "isDateInTomorrow",
    ]).union(propertyMarkers)

    /// Markers that read ambient state as properties, so a key path naming one refutes too.
    static let propertyMarkers: Set<String> = ["timeIntervalSinceNow", "autoupdatingCurrent"]

    private static let ambientCurrentTypes: Set<String> = ["Calendar", "NSCalendar", "NSLocale"]
    private static let freshConstructions: Set<String> = ["DateInterval", "NSDate", "NSUUID"]
    private static let nowByDefaultMembers: Set<String> = [
        "secondsFromGMT", "isDaylightSavingTime", "daylightSavingTimeOffset", "nextDaylightSavingTimeTransition"
    ]
    private static let baseLessNondeterministicMarkers: Set<String> = ["now"]

    /// `PurityInferrer.tokenMarker`, as a yes or no. `markers` stands in for the two marker sets, so the truncation
    /// control can remove one; every other rule is SEI's, copied.
    static func tokenRefutes(_ token: TokenSyntax, markers: Set<String>) -> Bool {
        if markers.contains(token.text), isMarkerPosition(token) { return true }
        if baseLessNondeterministicMarkers.contains(token.text), isBaseLessMember(token) { return true }
        if ambientCurrentType(of: token) != nil { return true }
        if isFreshConstruction(token) { return true }
        if token.text == "now", isBridgedNow(token) { return true }
        return readsNowByDefault(token) || isAmbientFormatting(token)
    }

    /// `PurityInferrer.isMarkerPosition`, re-derived (SEI `caa37ca`, then #31's `8c800d6`): a marker is an identifier,
    /// and a key path's component only when it is a property marker. The text of a string literal is not code —
    /// `"Date"` names nothing. Every token scan in these censuses goes through this, so they cannot disagree about it.
    static func isMarkerPosition(_ token: TokenSyntax) -> Bool {
        guard case .identifier = token.tokenKind else { return false }
        if let reference = token.parent?.as(DeclReferenceExprSyntax.self),
           reference.parent?.is(KeyPathPropertyComponentSyntax.self) == true {
            return propertyMarkers.contains(token.text)
        }
        return true
    }

    static func isBaseLessMember(_ token: TokenSyntax) -> Bool {
        guard let reference = token.parent?.as(DeclReferenceExprSyntax.self),
              let member = reference.parent?.as(MemberAccessExprSyntax.self) else { return false }
        return member.base == nil && member.declName.id == reference.id
    }

    static func ambientCurrentType(of token: TokenSyntax) -> String? {
        guard token.text == "current",
              let reference = token.parent?.as(DeclReferenceExprSyntax.self),
              let member = reference.parent?.as(MemberAccessExprSyntax.self),
              member.declName.id == reference.id,
              let base = member.base?.as(DeclReferenceExprSyntax.self),
              ambientCurrentTypes.contains(base.baseName.text) else { return nil }
        return base.baseName.text
    }

    static func isFreshConstruction(_ token: TokenSyntax) -> Bool {
        guard freshConstructions.contains(token.text),
              let reference = token.parent?.as(DeclReferenceExprSyntax.self) else { return false }
        var callee = Syntax(reference)
        if let member = reference.parent?.as(MemberAccessExprSyntax.self), member.base?.id == reference.id,
           member.declName.baseName.tokenKind == .keyword(.`init`) {
            callee = Syntax(member)
        }
        guard let call = callee.parent?.as(FunctionCallExprSyntax.self), call.calledExpression.id == callee.id else {
            return false
        }
        return call.arguments.isEmpty && call.trailingClosure == nil
    }

    static func isBridgedNow(_ token: TokenSyntax) -> Bool {
        guard let reference = token.parent?.as(DeclReferenceExprSyntax.self),
              let member = reference.parent?.as(MemberAccessExprSyntax.self),
              member.declName.id == reference.id,
              let base = member.base?.as(DeclReferenceExprSyntax.self) else { return false }
        return base.baseName.text == "NSDate"
    }

    static func readsNowByDefault(_ token: TokenSyntax) -> Bool {
        guard nowByDefaultMembers.contains(token.text),
              let reference = token.parent?.as(DeclReferenceExprSyntax.self) else { return false }
        if reference.parent?.is(KeyPathPropertyComponentSyntax.self) == true { return true }
        guard let member = reference.parent?.as(MemberAccessExprSyntax.self),
              member.declName.id == reference.id else { return false }
        guard let call = member.parent?.as(FunctionCallExprSyntax.self), call.calledExpression.id == member.id else {
            return true
        }
        return call.arguments.isEmpty && call.trailingClosure == nil
    }

    static func isAmbientFormatting(_ token: TokenSyntax) -> Bool {
        guard token.text == "formatted",
              let reference = token.parent?.as(DeclReferenceExprSyntax.self),
              let member = reference.parent?.as(MemberAccessExprSyntax.self),
              member.base != nil, member.declName.id == reference.id,
              let call = member.parent?.as(FunctionCallExprSyntax.self),
              call.calledExpression.id == member.id else { return false }
        if call.arguments.contains(where: { $0.label?.text == "using" }) { return false }
        guard call.arguments.count == 1, let style = call.arguments.first, style.label == nil else { return true }
        return baseLessRoot(of: style.expression) != "iso8601"
    }

    private static func baseLessRoot(of expression: ExprSyntax) -> String? {
        if let call = expression.as(FunctionCallExprSyntax.self) { return baseLessRoot(of: call.calledExpression) }
        guard let member = expression.as(MemberAccessExprSyntax.self) else { return nil }
        guard let base = member.base else { return member.declName.baseName.text }
        return baseLessRoot(of: base)
    }

    // MARK: - A default judged with its parameter's type (SEI #31, `d98f8d5` and `f9e0ddb`)

    /// `PurityInferrer.typeRefutation`: a default holding an implicit member (`at: Date = .init()`,
    /// `calendar: Calendar = .current`) is judged with the parameter's type in front of it.
    ///
    /// **The marker half is re-derived; `RawDeclaration.judge` is consulted, not re-derived**, on the construction
    /// cause's precedent (`constructionWitness`): it is SEI's construction machinery, and a second copy of it is the
    /// drift `verdictAgreesWithSoundPurity` exists to catch. SEI's `refutation(for:)` names only its FIRST witness,
    /// so a default refuted this way behind a body marker reads as `.marker` alone: the verdict is the same, and the
    /// `markerInDefault` cause can be under-attributed by that overlap.
    func typedDefaultRefutes(_ parameter: FunctionParameterSyntax, of function: FunctionDeclSyntax) -> Bool {
        guard let value = parameter.defaultValue?.value, Self.holdsImplicitMember(value) else { return false }
        if hasMarker(in: parameter.type) { return true }
        let name = parameter.secondName?.text ?? parameter.firstName.text
        if case let .refutingDefaultArgument(parameter: refuted, cause: _) = inferrer.refutation(for: function) {
            return refuted == name
        }
        return false
    }

    /// `ImplicitMemberChecker`: a member access with no base anywhere in `syntax`.
    static func holdsImplicitMember(_ syntax: some SyntaxProtocol) -> Bool {
        syntax.tokens(viewMode: .sourceAccurate).contains { token in
            guard let reference = token.parent?.as(DeclReferenceExprSyntax.self),
                  let member = reference.parent?.as(MemberAccessExprSyntax.self) else { return false }
            return member.base == nil
        }
    }
}
