// Verify-ready corpus for the reorder-partition measured path.
//
// Five `mutating` partition methods on `[Int]`: three that honour the law (a
// stable whole-collection partition, a correct non-stable one, and a stable
// subrange partition) and two that break it in distinct ways — a whole-collection
// partition that DROPS an element (permutation violation) and a subrange
// partition that reorders the WHOLE array ignoring the fence (the exact
// swift-algorithms `stablePartition(subrange:by:)` `0dba0e5` failure mode).
//
// Only execution tells the good from the bad — every name reads like a partition.
// The stub (`ReorderPartitionStubEmitter`) verifies each and the measured test
// asserts the bothPass / defaultFails split.

extension Array {

    /// Correct **stable** whole-collection partition: elements failing the
    /// predicate keep their order and come first, satisfying ones follow.
    mutating func stablePartitionWhole(by belongsInSecondPartition: (Element) -> Bool) -> Int {
        let firstGroup = self.filter { !belongsInSecondPartition($0) }
        let secondGroup = self.filter { belongsInSecondPartition($0) }
        self = firstGroup + secondGroup
        return firstGroup.count
    }

    /// BUGGY: drops the first satisfying element, so the result is not a
    /// permutation of the input — caught by the multiset law.
    mutating func buggyDropWhole(by belongsInSecondPartition: (Element) -> Bool) -> Int {
        let firstGroup = self.filter { !belongsInSecondPartition($0) }
        var secondGroup = self.filter { belongsInSecondPartition($0) }
        if !secondGroup.isEmpty { secondGroup.removeFirst() }
        self = firstGroup + secondGroup
        return firstGroup.count
    }

    /// Correct but **non-stable** whole-collection partition (a swap-based
    /// in-place move): the split and permutation laws hold, relative order does
    /// not — so it verifies only under the non-stable check.
    mutating func unstablePartitionWhole(by belongsInSecondPartition: (Element) -> Bool) -> Int {
        var pivot = 0
        for index in 0..<count where !belongsInSecondPartition(self[index]) {
            swapAt(pivot, index)
            pivot += 1
        }
        return pivot
    }

    /// Correct **stable** subrange partition: only the subrange is reordered,
    /// everything outside stays put, and the pivot lands inside the subrange.
    mutating func stablePartitionSubrange(
        subrange: Range<Int>,
        by belongsInSecondPartition: (Element) -> Bool
    ) -> Int {
        let slice = Array(self[subrange])
        let firstGroup = slice.filter { !belongsInSecondPartition($0) }
        let secondGroup = slice.filter { belongsInSecondPartition($0) }
        replaceSubrange(subrange, with: firstGroup + secondGroup)
        return subrange.lowerBound + firstGroup.count
    }

    /// BUGGY (the `0dba0e5` shape): reorders the WHOLE array instead of just the
    /// subrange, so elements outside the fence move — caught by the fence law.
    mutating func buggyFenceSubrange(
        subrange: Range<Int>,
        by belongsInSecondPartition: (Element) -> Bool
    ) -> Int {
        let firstGroup = self.filter { !belongsInSecondPartition($0) }
        let secondGroup = self.filter { belongsInSecondPartition($0) }
        self = firstGroup + secondGroup
        return subrange.lowerBound + self[subrange].filter { !belongsInSecondPartition($0) }.count
    }
}
