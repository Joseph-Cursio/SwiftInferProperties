import SwiftInferCore

extension LiftedSuggestion {

    // MARK: - Explainability

    func makeExplainability() -> ExplainabilityBlock {
        if case .equivalenceClass(let hint) = pattern {
            return equivalenceClassExplainability(hint: hint)
        }
        if case .nClassEquivalenceClass(let hint) = pattern {
            return nClassEquivalenceClassExplainability(hint: hint)
        }
        if case .consumerProducerChain(let hint) = pattern {
            return consumerProducerChainExplainability(hint: hint)
        }
        let assertionLine: String
        switch pattern {
        case .roundTrip(let detection):
            assertionLine = "Test body asserts \(detection.backwardCallee)"
                + "(\(detection.forwardCallee)(\(detection.inputBindingName)))"
                + " == \(detection.inputBindingName)"

        case .idempotence(let detection):
            assertionLine = "Test body asserts \(detection.calleeName)"
                + "(\(detection.calleeName)(\(detection.inputBindingName)))"
                + " == \(detection.calleeName)(\(detection.inputBindingName))"

        case .commutativity(let detection):
            assertionLine = "Test body asserts \(detection.calleeName)"
                + "(\(detection.leftArgName), \(detection.rightArgName))"
                + " == \(detection.calleeName)(\(detection.rightArgName), \(detection.leftArgName))"

        case .monotonicity(let detection):
            assertionLine = "Test body asserts \(detection.leftArgName)"
                + " < \(detection.rightArgName) implies "
                + "\(detection.calleeName)(\(detection.leftArgName))"
                + " <= \(detection.calleeName)(\(detection.rightArgName))"

        case .countInvariance(let detection):
            assertionLine = "Test body asserts \(detection.calleeName)"
                + "(\(detection.inputBindingName)).count"
                + " == \(detection.inputBindingName).count"

        case .reduceEquivalence(let detection):
            assertionLine = "Test body asserts \(detection.collectionBindingName)"
                + ".reduce(\(detection.seedSource), \(detection.opCalleeName))"
                + " == \(detection.collectionBindingName).reversed()"
                + ".reduce(\(detection.seedSource), \(detection.opCalleeName))"

        case .equivalenceClass, .nClassEquivalenceClass, .consumerProducerChain:
            // Handled by the early-return above.
            assertionLine = ""
        }
        let location = assertionLocation()
        let provenance = "Lifted from \(location.file):\(location.line)"
        return ExplainabilityBlock(
            whySuggested: [assertionLine, provenance],
            whyMightBeWrong: []
        )
    }

    /// M11.2 — equivalence-class explainability surfaces the corpus
    /// observation (predicate, marker pair, bucket counts) plus either
    /// the suggested filter generators or the predicate-shape veto
    /// reason. Distinct from the assertion-line shape used for the
    /// other six patterns because equivalence-class findings aren't
    /// anchored on a single test-body assertion.
    private func equivalenceClassExplainability(hint: EquivalenceClassHint) -> ExplainabilityBlock {
        let header = "Predicate \(hint.predicateName)(_: \(hint.argTypeName)) -> Bool"
            + " partitions Valid/Invalid across the test corpus:"
        let positiveLine = "  • \(hint.positiveSiteCount) sites named \(hint.positiveMarker)*"
            + " assert \(hint.predicateName)(x) is true"
        let negativeLine = "  • \(hint.negativeSiteCount) sites named \(hint.negativeMarker)*"
            + " assert \(hint.predicateName)(x) is false"
        var why = [header, positiveLine, negativeLine]
        if let veto = hint.predicateVeto {
            why.append("Generator narrowing skipped: \(veto.advisoryReason).")
        } else {
            why.append("Suggested generator for \(hint.positiveMarker) class: "
                + hint.suggestedPositiveGenerator)
            why.append("Suggested generator for \(hint.negativeMarker) class: "
                + hint.suggestedNegativeGenerator)
        }
        let advisoryCaveat = "Advisory only — the equivalence class is documentation,"
            + " not a runnable property. Author per-class properties"
            + " manually using the suggested filter generators."
        let rejectionCaveat = "Filter rejection rate: \(hint.predicateName) may reject most"
            + " random \(hint.argTypeName)s; if so, prefer constructing"
            + " a custom Gen for the \(hint.positiveMarker) class instead"
            + " of relying on filter."
        return ExplainabilityBlock(whySuggested: why, whyMightBeWrong: [advisoryCaveat, rejectionCaveat])
    }

    private func assertionLocation() -> SourceLocation {
        switch pattern {
        case .roundTrip(let detection):
            return detection.assertionLocation

        case .idempotence(let detection):
            return detection.assertionLocation

        case .commutativity(let detection):
            return detection.assertionLocation

        case .monotonicity(let detection):
            return detection.assertionLocation

        case .countInvariance(let detection):
            return detection.assertionLocation

        case .reduceEquivalence(let detection):
            return detection.assertionLocation

        case .equivalenceClass, .nClassEquivalenceClass, .consumerProducerChain:
            // M11.2 / M13.3 / M16.2 — corpus-level finding; no single
            // assertion location.
            return SourceLocation(file: "<corpus>", line: 0, column: 0)
        }
    }

    /// M13.3 — explainability for N-class equivalence-class advisory.
    /// Mirrors `equivalenceClassExplainability(hint:)` for the two-class
    /// case but lists per-bucket marker counts and per-bucket suggested
    /// generators (or the predicate-shape veto reason).
    private func nClassEquivalenceClassExplainability(hint: NClassEquivalenceClassHint) -> ExplainabilityBlock {
        let header = "Predicate \(hint.predicateName)(_: \(hint.argTypeName))"
            + " -> \(hint.returnTypeName) partitions \(hint.markerSetName)"
            + " across the test corpus:"
        var why = [header]
        for marker in hint.markers {
            let count = hint.siteCountsByMarker[marker] ?? 0
            why.append("  • \(count) sites named \(marker)*"
                + " assert \(hint.predicateName)(x) == .\(marker.lowercasedFirst())")
        }
        if let veto = hint.predicateVeto {
            why.append("Generator narrowing skipped: \(veto.advisoryReason).")
        } else {
            for marker in hint.markers {
                if let generator = hint.suggestedGeneratorsByMarker[marker] {
                    why.append("Suggested generator for \(marker) class: \(generator)")
                }
            }
        }
        if hint.coversDomain {
            why.append("Exhaustiveness: forAll x: \(hint.argTypeName)."
                + " disjunction over \(hint.markers.count) buckets covers"
                + " every case of \(hint.returnTypeName).")
        }
        let advisoryCaveat = "Advisory only — the equivalence class is documentation,"
            + " not a runnable property. Author per-class properties manually using"
            + " the suggested filter generators."
        return ExplainabilityBlock(whySuggested: why, whyMightBeWrong: [advisoryCaveat])
    }
}

private extension String {
    /// Marker text in vocabulary is conventionally Title-cased; Swift
    /// enum cases are lowercase-first. Used in renderer output.
    func lowercasedFirst() -> String {
        guard let first = self.first else { return self }
        return first.lowercased() + self.dropFirst()
    }
}
