extension SetupRegionConstructionScanner {

    /// Type name ascending, canonical label key ascending as the tiebreak.
    ///
    /// The tiebreak is the whole point here: entries are keyed on
    /// `(typeName, shape)`, so every type with more than one construction shape
    /// produces a tie on the first key by construction.
    static func byTypeNameThenShapeLabel(
        _ lhs: ConstructionRecordEntry, _ rhs: ConstructionRecordEntry
    ) -> Bool {
        (lhs.typeName, lhs.shape.canonicalLabelKey)
            < (rhs.typeName, rhs.shape.canonicalLabelKey)
    }
}
