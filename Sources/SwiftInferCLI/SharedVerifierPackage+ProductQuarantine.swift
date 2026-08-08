import Foundation

/// Keep one member's unresolvable product edge from failing the whole survey.
///
/// `SharedVerifierPackage`'s doc records a measured property: building
/// `--product` per member means one bad stub costs **one** entry, where a whole-
/// package `swift build` costs all 53. That isolation is real, and it covers
/// *compilation* only. A `.product(name:package:)` naming a product the corpus
/// does not vend fails **manifest loading**, which happens before any target is
/// built — so the attribution guarantee that file was written to preserve does
/// not hold against this class of error at all.
///
/// Measured on swift-collections (#169 follow-on): one `BigString` carrier
/// resolved to product `RopeModule`, which the package does not vend — its
/// product is `_RopeModule`, and there is no `RopeModule` target either, so the
/// name came from `libraryProduct(exposingModule:)` returning `nil` and the
/// caller falling back to the module name. Result: `error: product 'RopeModule'
/// … not found in package 'swift-collections'`, and **all 54** buildable entries
/// recorded `build-failed`. 53 of them had nothing wrong with them.
///
/// So the fallback is quarantined rather than removed. Removing it would decline
/// every entry whose module is not vended as a product, which is the same answer
/// for this corpus and a worse one in general: the fallback is correct whenever
/// product and module share a name, which is the common case. What must not
/// happen is an *unvalidated* guess reaching the manifest.
///
/// Validation is against the corpus's real product list, and covers the built-in
/// edges too — when a URL dependency is superseded by the corpus
/// (`VerifierWorkdir+CorpusIdentity`), edges like
/// `.product(name: "DequeModule", package: "swift-collections")` resolve against
/// the corpus from then on, so they are exactly as capable of naming something it
/// does not vend.
extension SharedVerifierPackage {

    /// A member that cannot be given a target, and the reason a reader can act on.
    struct Quarantined {
        let member: Member
        /// Rendered into the entry's `outcomeDetail`.
        let reason: String
    }

    /// Split members into those whose product edges all resolve and those whose
    /// do not.
    ///
    /// A corpus whose manifest cannot be read at all yields `nil` from
    /// `libraryProductNames` — its members pass through **unvalidated** rather
    /// than being quarantined wholesale. An unreadable manifest is not evidence
    /// that a product is missing, and turning "I could not check" into "your
    /// carrier is unreachable" would be the same category error this whole family
    /// of bugs keeps making.
    static func quarantiningUnresolvableProducts(
        _ members: [Member]
    ) -> (usable: [Member], quarantined: [Quarantined]) {
        var productsByCorpus: [String: Set<String>?] = [:]
        var usable: [Member] = []
        var quarantined: [Quarantined] = []

        for member in members {
            guard let corpus = member.userPackage else {
                usable.append(member)
                continue
            }
            let key = corpus.packagePath.path
            let vended: Set<String>?
            if let cached = productsByCorpus[key] {
                vended = cached
            } else {
                vended = PackageProductResolver.libraryProductNames(packageRoot: corpus.packagePath)
                productsByCorpus[key] = vended
            }
            guard let vended else {
                usable.append(member)
                continue
            }
            let missing = requiredCorpusProducts(of: member).filter { !vended.contains($0) }
            if missing.isEmpty {
                usable.append(member)
            } else {
                quarantined.append(
                    Quarantined(
                        member: member,
                        reason: "unsupported-carrier: \(missing.sorted().joined(separator: ", ")) "
                            + "is not a library product of \(corpus.packageIdentity) "
                            + "(vended: \(vended.sorted().prefix(6).joined(separator: ", "))"
                            + (vended.count > 6 ? ", …" : "") + ")"
                    )
                )
            }
        }
        return (usable, quarantined)
    }

    /// Product names this member asks the **corpus** for.
    ///
    /// Read back off the rendered target-dependency block rather than from
    /// `productNames`, because the built-in edges can name the corpus too once a
    /// URL dependency is superseded, and those are not in `productNames`. Same
    /// read-the-renderer discipline `packageDependencies(of:)` uses, for the same
    /// reason: a second list of "what does this target link" would drift.
    private static func requiredCorpusProducts(of member: Member) -> [String] {
        guard let corpus = member.userPackage else { return [] }
        let identity = corpus.packageIdentity.lowercased()
        let block = VerifierWorkdir.renderTargetDependenciesBlock(
            userPackage: corpus, mode: member.mode
        )
        return block.components(separatedBy: "\n").compactMap { line in
            guard let packageRange = line.range(of: "package: \""),
                  let nameRange = line.range(of: "name: \"") else { return nil }
            let afterPackage = line[packageRange.upperBound...]
            guard let packageEnd = afterPackage.firstIndex(of: "\""),
                  String(afterPackage[..<packageEnd]).lowercased() == identity else { return nil }
            let afterName = line[nameRange.upperBound...]
            guard let nameEnd = afterName.firstIndex(of: "\"") else { return nil }
            return String(afterName[..<nameEnd])
        }
    }
}
