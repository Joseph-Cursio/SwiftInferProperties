I asked ChaptGPT:
>Is there a spectrum of testing between unit tests and program verification? 

_FYI: ChatGPT summarizes to these (and Copilot does as well): 
1. unit testing, 
2. property-based testing, 
3. model-based testing, and 
4. Formal verification.

---

Yes—there’s very much a _spectrum_ (or more accurately, several overlapping spectra) between traditional unit testing and full formal program verification. Thinking of it as a gradient helps clarify tradeoffs in rigor, cost, and guarantees.

Here’s a useful way to map that space from “lightweight / empirical” to “heavyweight / mathematical certainty”:

---

### **1. Example-Based Testing (Unit Tests)**

- Write specific inputs → assert expected outputs.
- Fast, cheap, and localized.
- Weak guarantees: only covers what you thought to test.

👉 This is where most everyday development lives.

---

### **2. Property-Based Testing**

- Instead of examples, you define _properties_ (invariants).
- A tool generates many inputs to try to break them.
- Think QuickCheck-style: “this function is idempotent,” “sorting preserves length,” etc.

**Key shift:** from _examples_ → _general behaviors_  
Still empirical, but much broader coverage.

---

### **3. Fuzz Testing**

- Random or mutation-based input generation at scale.
- Often used for robustness/security.
- Less semantic than property testing—more about “does it crash?”

---

### **4. Contract-Based Programming**

- Pre-conditions, post-conditions, invariants embedded in code.
- Can be checked at runtime or statically (depending on tooling).

This starts to blur into verification because you’re specifying _intent formally_.

---

### **5. Symbolic Execution**

- Instead of running with concrete values, the program runs with symbolic inputs.
- Explores many execution paths simultaneously.
- Can detect edge cases unit tests will never hit.

Tradeoff: path explosion → doesn’t scale easily.

---

### **6. Static Analysis / Abstract Interpretation**

- Analyzes code without running it.
- Can prove absence of certain classes of bugs (e.g., null dereferences, data races).
- Soundness varies depending on the tool.

This is where “semantic linting” (like what you mentioned building) starts becoming powerful.

---

### **7. Model Checking**

- You model the system (or parts of it) and exhaustively explore all states.
- Often used in concurrent or distributed systems.

Strong guarantees—but usually requires simplification of the system.

---

### **8. Formal Verification**

- You write a _specification_ and prove the program satisfies it.
- Uses theorem provers or proof assistants.

Examples:

- Proving sorting correctness
- Verifying cryptographic protocols

Highest assurance, but:

- Expensive
- Requires expertise
- Often impractical for entire systems

---

## **Another Way to View the Spectrum**

You can also think in terms of **what’s being specified**:

|**Level**|**What you specify**|**Technique**|
|---|---|---|
|Concrete cases|Inputs/outputs|Unit tests|
|Behavioral patterns|Properties|Property-based testing|
|Constraints|Contracts|DbC|
|Execution space|Paths|Symbolic execution|
|System model|States/transitions|Model checking|
|Full correctness|Formal spec|Verification|

---

## **The Key Insight**

The real continuum is:

**“How much of the program’s behavior is explicitly specified vs implicitly assumed?”**

- Unit tests → mostly implicit
- Property tests → partially explicit
- Contracts → locally explicit
- Verification → fully explicit

---

## **Where Things Get Interesting (and Practical)**

In modern practice, the sweet spot is often a hybrid:

- Unit tests for concrete behavior
- Property tests for invariants (like idempotency—your interest)
- Lightweight static analysis for structural guarantees
- Selective formal methods for critical components

This layered approach gives you **disproportionate reliability without full verification cost**.

---

If you want, I can map this spectrum specifically onto Swift tooling (e.g., SwiftSyntax, SourceKit, or how your semantic linter could evolve toward lightweight verification).