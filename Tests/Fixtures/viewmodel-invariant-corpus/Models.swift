// PROTOTYPE — verify-ready corpus for the three remaining state-invariant
// families. Each family pairs an invariant-maintaining model (bothPass)
// with an invariant-breaking one (defaultFails). Self-contained (Combine).

import Combine

// MARK: - Cardinality (≥2 presentation routes mutually exclusive)

final class RouterModel: ObservableObject {
    @Published var activeSheet: Int? = nil
    @Published var activeAlert: Int? = nil

    func showSheet() {
        activeSheet = 1
        activeAlert = nil
    }

    func showAlert() {
        activeAlert = 1
        activeSheet = nil
    }

    func dismiss() {
        activeSheet = nil
        activeAlert = nil
    }
}

final class LeakyRouterModel: ObservableObject {
    @Published var activeSheet: Int? = nil
    @Published var activeAlert: Int? = nil

    /// Does NOT clear the sibling route → driving showAlert then showSheet
    /// leaves both non-nil → cardinality violated → defaultFails.
    func showSheet() {
        activeSheet = 1
    }

    func showAlert() {
        activeAlert = 1
    }

    func dismiss() {
        activeSheet = nil
        activeAlert = nil
    }
}

// MARK: - Biconditional (Bool flag ⟺ Optional present)

final class SessionModel: ObservableObject {
    @Published var isActive: Bool = false
    @Published var activeToken: String? = nil

    func login(_ token: String) {
        activeToken = token
        isActive = true
    }

    func logout() {
        activeToken = nil
        isActive = false
    }
}

final class DriftModel: ObservableObject {
    @Published var isActive: Bool = false
    @Published var activeToken: String? = nil

    /// Sets the flag without the token → `isActive == (activeToken != nil)`
    /// is violated → defaultFails.
    func beginActivating() {
        isActive = true
    }

    func finishLogin(_ token: String) {
        activeToken = token
    }
}

// MARK: - Conservation (count ⟺ collection size)

final class CartModel: ObservableObject {
    @Published var items: [Int] = []
    @Published var itemCount: Int = 0

    func add(_ value: Int) {
        items.append(value)
        itemCount = items.count
    }

    func clear() {
        items.removeAll()
        itemCount = items.count
    }
}

final class BadgeModel: ObservableObject {
    @Published var items: [Int] = []
    @Published var itemCount: Int = 0

    func add(_ value: Int) {
        items.append(value)
        itemCount += 1
    }

    /// Clears the collection but NOT the count → `itemCount == items.count`
    /// is violated → defaultFails.
    func clearItems() {
        items.removeAll()
    }
}
