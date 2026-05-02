I asked Gemini: 
>How can I identify properties from existing Swift code?

**The best way to identify properties from existing Swift code is to look for** **_semantic guarantees the code already assumes_****—invariants, protocol laws, round‑trip behaviors, ordering rules, and structural constraints. These are almost always visible in the code’s shape, its protocols, and its data transformations.

Below is a structured, practical workflow you can apply to _any_ Swift codebase to systematically extract high‑value properties.

---

# **🧭 1. Start With Protocol Conformances (The Easiest Wins)**

Swift’s protocol‑oriented design makes protocol laws the richest source of properties. Whenever you see a type conform to a protocol, ask: _What laws must this protocol obey?_

### **Equatable**

Look for:

- **Reflexivity**  
    : x == x
- **Symmetry**  
    : x == y ⇒ y == x
- **Transitivity**  
    : x == y && y == z ⇒ x == z
- **Inequality consistency**  
    : x != y is the negation of equality

### **Comparable**

Look for:

- **Antisymmetry**  
    : if x < y then !(y < x)
- **Transitivity**  
    : x < y && y < z ⇒ x < z
- **Totality**  
    : exactly one of <, ==, or > must be true

### **Hashable**

Look for:

- **Equal values must have equal hashes**
- **Hash stability**  
    across repeated calls

### **Codable**

Look for:

- **Round‑trip**  
    : decode(encode(x)) == x

### **Collection / Sequence**

Look for:

- `count` matches number of elements
- Indexing invariants
- Iteration order stability

These protocol‑law properties are _always_ valid candidates because they reflect Swift’s semantic expectations.

---

# **🧭 2. Look for Pure Functions (Round‑Trip, Idempotence, and Composition)**

Scan the code for functions that:

- take inputs and return outputs
- do not mutate external state
- do not throw
- do not perform async work

These are **pure functions**, and pure functions almost always imply properties:

### **Round‑trip properties**

If you see pairs like:

- `encode` / `decode`
- `serialize` / `deserialize`
- `push` / `pop`
- `insert` / `remove`

Then you can propose:

> `decode(encode(x)) == x`

### **Idempotence**

If a function “normalizes” something:

- sorting
- trimming
- canonicalizing
- deduplicating

Then:

> `f(f(x)) == f(x)`

### **Composition**

If you see pipelines like:

```swift
let y = transformB(transformA(x))
```

Then you can test:

> `transformB ∘ transformA` preserves some invariant.

---

# **🧭 3. Inspect Data Structures for Structural Invariants**

Look at stored properties and initializers. Ask:

- What must always be true about this type?
- What constraints does the initializer enforce?
- What assumptions do methods make about internal state?

Examples:

- A `Range` must satisfy `lowerBound <= upperBound`.
- A `Tree` node’s children must not form cycles.
- A `Graph` marked “DAG” must have no cycles.
- A `Money` type may require currency consistency.

These invariants become **properties**.

---

# **🧭 4. Look for Guard Statements and Preconditions**

Every `guard`, `precondition`, or `assert` is a hint that the author expects something to always be true.

For example:

```swift
guard index < array.count else { return }
```

This suggests:

- For valid inputs, `index` should always be within bounds.
- If the function is supposed to maintain invariants, you can test that it _never produces_ an out‑of‑bounds index.

---

# **🧭 5. Look for Symmetry, Reversibility, and Dual Operations**

Many Swift APIs come in natural pairs:

- `map` vs `compactMap`
- `encode` vs `decode`
- `append` vs `removeLast`
- `push` vs `pop`

These pairs often imply:

- **Reversibility**
- **No‑op behavior**  
    (e.g., removing after adding returns to original state)
- **Order preservation**

---

# **🧭 6. Look for “Should Never Happen” Comments**

Comments like:

- “This case should never occur”
- “We assume the list is sorted”
- “This must always be non‑empty”

These are _gold mines_ for properties. If the author assumes it, you can test it.

---

# **🧭 7. Look for Repeated Patterns in Tests**

If the existing unit tests repeat the same structure with different inputs, that’s a sign the author is manually doing property‑based testing.

Convert repeated examples into a **generalized property**.

---

# **🧭 8. Look for Algebraic Structures**

If a type behaves like:

- a monoid (has identity + associative combine)
- a group (has inverse)
- a semigroup (associative combine)

Then you can test:

- **Associativity**
- **Identity laws**
- **Inverse laws**

Swift’s value types often implicitly form algebraic structures.

---

# **👉 If you want, I can take a real Swift file from your codebase and extract all candidate properties automatically — including protocol laws, invariants, round‑trip rules, and algebraic behaviors.**

