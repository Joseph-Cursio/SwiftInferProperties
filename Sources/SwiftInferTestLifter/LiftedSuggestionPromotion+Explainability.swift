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
        let assertionLine = assertionLineText()
        return ExplainabilityBlock(
            whySuggested: [assertionLine, provenanceLine()],
            whyMightBeWrong: []
        )
    }

    /// Where this law was read from, named so a reviewer can open the file.
    ///
    /// **Three tiers, because the most precise source is the one most often
    /// missing.** `Slicer` has no `SourceLocationConverter`, so the assertion's own
    /// location is `SourceLocation.testBodyPlaceholder` on every path that reaches
    /// `discover` — which is how every lifted row came to render
    /// `Lifted from <test-body>:0`, a placeholder and a zero, while source-derived
    /// rows in the same output carried `file.swift:line`.
    ///
    /// That is not cosmetic. It is what let the package-wide test-lifting defect
    /// survive: a row citing `render(suggestion)` on `SwiftInferKitEvidence` reads
    /// as a plausible finding until it says which file it came from, and the defect
    /// was eventually found by noticing four byte-identical rows across six targets
    /// and grepping — not by reading output that could not say
    /// (`docs/measurements/roadtest-self-dogfood-2026-08-08.md` §7.4).
    ///
    /// `LiftedOrigin` has carried the enclosing test method's real file and line
    /// since M3.2 for the accept-flow's provenance header; the renderer simply
    /// never consulted it. Naming the METHOD rather than the assertion line is a
    /// deliberate trade — less precise, and true, which the placeholder was not.
    func provenanceLine() -> String {
        let assertion = assertionLocation()
        if assertion.isResolvable {
            return "Lifted from \(assertion)"
        }
        if let origin, origin.sourceLocation.isResolvable {
            return "Lifted from \(origin.sourceLocation.file):"
                + "\(origin.sourceLocation.line) `\(origin.testMethodName)`"
        }
        // Both unresolvable: say so plainly rather than printing `<test-body>:0`,
        // which reads like a path a reader could open and is not one.
        return "Lifted from a test body (exact location unavailable)"
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

        case .referenceEquivalence(let detection):
            return detection.location

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

    /// The "Test body asserts …" line, per pattern. Split from
    /// `explainability()` to stay under the complexity and length caps.
    private func assertionLineText() -> String {
        switch pattern {
        case .roundTrip(let detection):
            return "Test body asserts \(detection.backwardCallee)"
                + "(\(detection.forwardCallee)(\(detection.inputBindingName)))"
                + " == \(detection.inputBindingName)"

        case .referenceEquivalence(let detection):
            return "Test body checks `\(detection.subjectCallee)"
                + "(\(detection.sharedInput))` against the reference computation "
                + "`\(detection.referenceCallee)(\(detection.sharedInput))`"
                + (detection.directionIsCertain
                    ? " — the reference is a method on the input, so `"
                        + detection.subjectCallee + "` is the implementation under test"
                    : " — WHICH SIDE IS THE REFERENCE IS A GUESS from source order; "
                        + "confirm before treating a counterexample as `"
                        + detection.subjectCallee + "`'s bug")

        case .idempotence(let detection):
            return "Test body asserts \(detection.calleeName)"
                + "(\(detection.calleeName)(\(detection.inputBindingName)))"
                + " == \(detection.calleeName)(\(detection.inputBindingName))"

        case .commutativity(let detection):
            return "Test body asserts \(detection.calleeName)"
                + "(\(detection.leftArgName), \(detection.rightArgName))"
                + " == \(detection.calleeName)(\(detection.rightArgName), \(detection.leftArgName))"

        case .monotonicity(let detection):
            return "Test body asserts \(detection.leftArgName)"
                + " < \(detection.rightArgName) implies "
                + "\(detection.calleeName)(\(detection.leftArgName))"
                + " <= \(detection.calleeName)(\(detection.rightArgName))"

        case .countInvariance(let detection):
            return "Test body asserts \(detection.calleeName)"
                + "(\(detection.inputBindingName)).count"
                + " == \(detection.inputBindingName).count"

        case .reduceEquivalence(let detection):
            return "Test body asserts \(detection.collectionBindingName)"
                + ".reduce(\(detection.seedSource), \(detection.opCalleeName))"
                + " == \(detection.collectionBindingName).reversed()"
                + ".reduce(\(detection.seedSource), \(detection.opCalleeName))"

        case .equivalenceClass, .nClassEquivalenceClass, .consumerProducerChain:
            // Handled by the early-return above.
            return ""
        }
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
