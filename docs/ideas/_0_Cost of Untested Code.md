I asked ChatGPT:
> Some people say that the cost of code is dropping because of ai agents. Could one claim that is only true of untested code?

That claim is directionally right, but too simplistic.

What _is_ dropping in cost is **the production of raw, unvalidated code**—the “first draft.” AI agents can now generate large amounts of plausible code extremely cheaply. If you define “code” narrowly as “lines written,” then yes, the cost is collapsing.

But in real systems, code isn’t valuable until it’s **trusted**. That’s where the nuance comes in:

### **1. Tested vs. untested code is a real dividing line**

- **Untested code**: Cheap, abundant, often disposable
- **Well-tested, production-grade code**: Still expensive

Testing isn’t just writing unit tests. It includes:

- Correctness under edge cases
- Integration behavior
- Performance characteristics
- Security properties
- Long-term maintainability

AI can help with tests, but it doesn’t eliminate the need for **judgment about what to test and why**.

### **2. The bottleneck is shifting, not disappearing**

Historically:

Writing code was the bottleneck

Now:

**Understanding, validating, and maintaining code** is the bottleneck

This includes:

- Reviewing AI-generated code
- Designing meaningful test coverage
- Debugging subtle failures
- Ensuring consistency across a system

So the _total_ cost of delivering reliable software hasn’t dropped nearly as fast as the cost of generating code.

### 

### 

### 

### 

### **3. AI can also generate**

**tested**

**code—but not**

**trusted**

**code**

Even when an agent produces:

- Unit tests
- Type-safe code
- Passing CI

…it can still fail in production due to:

- Incorrect assumptions
- Missing invariants
- Poor system-level reasoning

So the real scarce resource becomes:

**Confidence**, not code

### **4. A better framing**

Instead of:

“Code is getting cheaper”

A more accurate statement is:

**“The cost of exploring implementations is collapsing; the cost of certainty is not.”**

### **5. Your hypothesis, refined**

Your idea can be sharpened into something quite defensible:

“AI reduces the cost of producing unverified code, but the cost of producing _reliable, production-grade systems_ remains high because validation, testing strategy, and system understanding are still hard.”

That’s a strong claim—and it aligns with what many teams are actually experiencing.

---

The “code is cheap, certainty is expensive” idea plays out very differently depending on the kind of system you’re building. In some domains AI meaningfully lowers _total_ cost; in others it mostly just shifts where humans spend time.

Here’s a breakdown that tends to match what teams are seeing:

---

## **1) UI / Frontend Apps (React, SwiftUI, etc.)**

**What AI makes cheap:**

- Boilerplate components
- Layouts, forms, bindings
- Basic state management

**What remains expensive:**

- UX correctness (does this actually behave how users expect?)
- Edge cases in state (loading, errors, race conditions)
- Cross-device quirks
- Product decisions disguised as “implementation”

**Net effect:**

- Big productivity gains
- Faster iteration cycles
- But still human-heavy validation

👉 In this domain, AI _does_ lower total cost meaningfully, because:

- Failures are visible and reversible
- Testing is often informal (human-driven)

---

## **2) CRUD / Internal Tools / Business Apps**

**What AI makes cheap:**

- Endpoints, models, schemas
- Admin panels, dashboards
- Glue code between systems

**What remains expensive:**

- Data correctness
- Business rule accuracy
- Migration safety
- Long-term maintainability

**Hidden risk:**  
AI can generate something that _looks right_ but encodes subtly wrong business logic.

**Net effect:**

- Faster initial delivery
- But higher risk of “quietly wrong” systems

👉 This is where your hypothesis shines:

Untested (or poorly validated) code is cheap—but correctness is still costly.

---

## **3) APIs & Distributed Systems**

**What AI makes cheap:**

- Service scaffolding
- Basic handlers and serialization
- Retry logic patterns (superficially)

**What remains expensive:**

- Concurrency correctness
- Failure modes (timeouts, partial failure, retries)
- Observability
- Data consistency guarantees

**Why this is hard:**  
These systems fail in _non-local_ ways. You don’t see the bug where it is.

**Net effect:**

- Code generation is faster
- System reliability is _not_ easier

👉 Here, AI mostly increases the **rate at which you can create bugs** unless you have strong discipline.

---

## **4) Performance-Critical Systems (e.g., low-latency, high-scale)**

**What AI makes cheap:**

- Naive implementations
- Baseline algorithms

**What remains expensive:**

- Profiling and bottleneck analysis
- Cache behavior, memory layout
- Algorithmic efficiency
- Hardware-aware tuning

**Key issue:**AI tends to produce _correct but suboptimal_ code.

**Net effect:**

- Little change to the hardest parts
- Experts still required

---

## **5) Safety-Critical Systems (medical, aviation, finance risk)**

**What AI makes cheap:**

- Draft implementations
- Documentation
- Test scaffolding

**What remains expensive (and dominant):**

- Formal verification / validation
- Regulatory compliance
- Traceability (requirements → implementation → tests)
- Auditing and certification

**Net effect:**

- Almost no reduction in total system cost

👉 In this world:

Untested code is not just useless—it’s a liability.

---

## **6) Libraries / SDKs / Public APIs**

**What AI makes cheap:**

- First-pass API designs
- Language bindings
- Examples and docs

**What remains expensive:**

- API _design quality_ (hard to change later)
- Backward compatibility
- Developer ergonomics
- Long-term support

**Net effect:**

- Faster prototyping
- But design mistakes are amplified

---

## **The pattern across all categories**

AI reduces:

**The cost of producing possibilities**

But not:

**The cost of choosing, validating, and maintaining the right one**

---

## **A sharper mental model**

Instead of thinking in terms of “tested vs. untested,” it helps to think in layers:

1. **Syntactic correctness** (AI is excellent here)
2. **Local correctness** (unit tests, types — AI is decent)
3. **System correctness** (interactions, invariants — still hard)
4. **Real-world correctness** (user behavior, production chaos — very hard)

AI dramatically compresses the cost of levels 1–2.

Most of the real engineering cost lives in levels 3–4.

---

## **Bottom line**

Your intuition holds, but here’s the refined version:

AI makes _code generation_ cheap across all domains, but only significantly reduces _total system cost_ in domains where correctness is easy to observe and cheap to validate.

Or even more bluntly:

The harder it is to know you’re right, the less AI reduces your costs.

---

If you want, we can push this further into strategy—how teams should change their development process to actually capture the upside without drowning in subtly wrong code.

I responded:
> Sure, my first thought was to strengthen linting rules, and ensure a level of code coverage.

Strengthening linting and enforcing coverage is a good instinct—but on its own, it won’t solve the problem you’re aiming at.

It mainly reinforces **levels 1–2 (syntactic + local correctness)**. The risk with AI-generated code shows up more in **levels 3–4 (system + real-world correctness)**. So you’ll get cleaner code that can still be _wrong in important ways_.

A better strategy is to treat AI as something that **amplifies output**, and then build guardrails that scale your _confidence_, not just your style.

Here’s how to evolve your idea into something more robust:

---

## **1) Keep linting—but make it semantic, not just stylistic**

Traditional lint rules:

- Naming
- Formatting
- Simple anti-patterns

These don’t catch the real AI failure modes.

Instead, bias toward:

- **Invariant-focused linting**
    - e.g. “all async paths must handle cancellation”
    - “no network call without timeout”
- **Architecture constraints**
    - e.g. layering violations, forbidden dependencies
- **Domain rules**
    - e.g. “money must use decimal types, never floats”

Your idea of using SwiftSyntax is actually powerful here—you can encode _project-specific correctness rules_, not generic style rules.

👉 Think:

“What mistakes would a smart but context-blind agent make repeatedly?”

Then codify those.

---

## **2) Coverage is necessary—but not sufficient**

You’re right to require coverage, but raw % is easy to game.

AI will happily generate:

- Tests that mirror implementation
- Tests that assert trivialities
- Tests that don’t explore edge cases

Instead, push toward:

### **a) Behavioral coverage over line coverage**

- Test _outcomes_, not code paths
- Focus on:
    - edge cases
    - invalid inputs
    - failure modes

### **b) Mutation testing (if you want to go further)**

- Slightly change the code automatically
- If tests still pass → your tests are weak

This directly attacks the “looks tested but isn’t” problem.

---

## **3) Require “intent before implementation”**

This is one of the highest-leverage shifts with AI.

Before accepting generated code, require:

- A short spec:
    - What are the invariants?
    - What are the failure modes?
    - What assumptions are being made?

Even lightweight:

```
/// Invariants:
/// - IDs are globally unique
/// - Requests are idempotent
///
/// Failure modes:
/// - Network timeout
/// - Partial write
```

Why this matters:

- Forces the human (or agent) to **think in constraints**
- Gives reviewers something to validate against
- Makes subtle bugs visible

---

## 

## 

## **4) Strengthen code review in a**

**different**

**way**

Traditional review asks:

“Is this code correct?”

That doesn’t scale with AI output.

Shift to:

- “What assumptions is this making?”
- “What happens if this fails?”
- “What is _not_ being tested?”

You’re reviewing **reasoning**, not just code.

---

## **5) Add system-level tests earlier**

Especially for:

- APIs
- distributed systems
- stateful logic

Invest in:

- Integration tests
- Property-based tests (great with AI)
- Replay tests (real production scenarios)

This is where most AI-generated bugs surface.

---

## **6) Observability becomes part of correctness**

AI often produces code that works in the “happy path” but is opaque when it fails.

Require:

- Structured logging
- Metrics around critical paths
- Tracing for distributed flows

Because:

If you can’t see it fail, you can’t trust it in production.

---

## **7) Constrain the problem space (very underrated)**

Instead of letting AI generate anything, limit it:

- Strong typing
- Narrow interfaces
- Fewer patterns allowed

The smaller the space:

The less room there is for “plausible but wrong” code

---

## 

## **8) Treat AI output as**

**untrusted input**

This mental model helps a lot.

You wouldn’t:

- Execute raw user input
- Trust external data blindly

So don’t:

- Trust AI-generated code without validation layers

---

## **Where your idea fits**

What you proposed:

Strong linting + coverage

That’s a solid **foundation layer**. But by itself:

- It catches _sloppy code_
- It does _not_ catch _wrong systems_

---

## **The upgraded version of your strategy**

If I were to compress this into a practical stack:

1. **Semantic linting (SwiftSyntax-based)** ← your idea, leveled up
2. **Coverage + mutation testing**
3. **Required invariants/spec comments**
4. **Review for assumptions, not just correctness**
5. **Integration + property-based tests**
6. **Mandatory observability hooks**

---

## **Final thought**

AI doesn’t just lower the cost of code—it **raises the premium on taste, judgment, and constraint design**.

So the winning teams won’t be the ones with:

the best code generators

…but the ones with:

the best systems for _rejecting bad code quickly_

---

If you want, I can help you design a concrete SwiftSyntax rule set or a lightweight “AI-safe” PR checklist tailored to your workflow.

I responded with:
> I think this project is a start towards semantic linting https://github.com/Joseph-Cursio/SwiftProjectLint

I couldn’t pull structured metadata for your repo directly, but I _did_ sanity-check the space it lives in—and your instinct is exactly right: you’re aiming at a gap that tools like SwiftLint only partially cover.

Let me give you a thoughtful, _engineering-level_ take on what you’re building and where it could go.

---

## **1) You’re targeting the real limitation of existing linters**

Tools like SwiftLint are explicitly designed for:

- Style enforcement
- Common anti-patterns
- Some AST-based checks (via SwiftSyntax)

They’re widely used, but fundamentally:

They enforce **convention**, not **correctness**

Even their more advanced rules:

- are often opt-in
- can produce false positives
- rarely encode _domain-specific invariants_  

---

## **2) Your project’s direction (semantic linting) is the right abstraction**

From what you described earlier + the repo name, you’re pushing toward:

**Project-aware, semantics-aware linting**

That’s a big shift. It means moving from:

- “This looks wrong”  
    to:
- “This violates how _this system_ is supposed to behave”

That’s _exactly_ what AI-generated code breaks most often.

---

## **3) Where SwiftProjectLint can become genuinely differentiated**

If you want this to be more than “SwiftLint + custom rules,” the key is:

### **A. Encode invariants, not patterns**

Instead of:

- “Don’t use force unwrap”

Go toward:

- “All network calls must include timeout + retry policy”
- “This type must only be constructed via factory X”
- “These two fields must always change together”

👉 This is where semantic linting becomes _system safety_.

---

### **B. Leverage SwiftSyntax—but don’t stop at syntax**

Most tools stop at AST pattern matching.

The next level is:

- Data flow awareness (even partial)
- Call graph constraints
- Type usage patterns across modules

Even lightweight versions of this are _very_ high leverage.

---

### **C. Make rules composable and project-specific**

The biggest failure mode of linting tools is:

Teams turn rules off because they’re too generic

If your tool lets teams define rules like:

```swift
rule "NoRawMoneyMath" {
    forbid BinaryExpr where lhs.type == Double && context == "money"
}
```

You’ve crossed into something much more powerful.

---

## 

## 

## **4) Why this matters**

**more**

**in the AI era**

This connects directly to your earlier insight.

AI-generated code tends to:

- Look idiomatic
- Pass basic linting
- Pass shallow tests

But it often violates:

- Hidden assumptions
- Domain invariants
- Architectural boundaries

So your tool becomes:

A **defense layer against plausible-but-wrong code**

---

## **5) The real opportunity: “AI-aware linting”**

This is where I’d push you further.

You could explicitly design for:

- AI-generated PRs
- Agent workflows

Examples:

### **Detect “suspiciously generic” implementations**

- Functions with no edge-case handling
- Missing error paths
- Overly broad `catch` blocks

### **Flag “untested complexity”**

- Complex logic with no corresponding test references
- New branches not reflected in test files

### **Enforce “intent coupling”**

- Require invariants/comments when certain patterns appear

---

## **6) One strategic suggestion (high impact)**

If you do one thing:

**Make violations explainable in terms of system risk, not style**

Instead of:

- “Avoid using X”

Say:

- “This code path can violate idempotency under retry”
- “This introduces a potential double-write under failure”

That changes adoption dramatically.

---

## **7) How I’d position your project**

If I had to phrase it sharply:

“SwiftProjectLint is not a style linter—it’s a system correctness guardrail.”

That’s a very different category than SwiftLint.

---

## **8) Final thought**

You’re basically converging on this idea:

As AI makes code cheap, **constraints become the product**

Most teams don’t have a good way to encode those constraints today.

If your project nails that—even partially—you’re not just improving linting…

You’re defining a new layer in the toolchain.

---

If you want, I can review your repo structure or rules and suggest specific semantic checks that would give you the biggest real-world impact early.

I responded with:
> I’ll treat this as a design review + “what would actually move the needle early,” based on the direction you’re aiming for.

Since I don’t have the repo contents in front of me, I’ll focus on **high-leverage rule categories + how to implement them with SwiftSyntax** so you can translate directly into your codebase.

---

# 

# 

# **1) Start with rules that catch**

**expensive mistakes**

**, not common ones**

The biggest trap is building a lot of rules that feel useful but don’t prevent real bugs.

Prioritize rules where:

- The bug is subtle
- The impact is high
- AI is likely to introduce it

### **🔴 Category A: Concurrency & async correctness**

These are extremely high ROI.

**Example rules:**

### **“Missing cancellation handling”**

Detect async functions that:

- call `Task {}` or `withTaskGroup`
- but never check `Task.isCancelled`

👉 SwiftSyntax approach:

- Walk `FunctionDeclSyntax`
- If `async`, scan body for:
    - `Task.isCancelled`
    - or `try Task.checkCancellation()`
- If absent → warn

---

### **“Fire-and-forget Task usage”**

```swift
Task {
    await doSomething()
}
```

Flag unless:

- explicitly annotated (e.g. `// @detached-ok`)
- or result is captured

👉 Why:  
AI _loves_ generating these, and they cause subtle bugs.

---

# **2) Enforce architectural boundaries (huge payoff)**

This is where semantic linting becomes powerful.

### **🔴 Category B: Layer violations**

Example:

- UI layer importing networking
- Domain layer depending on persistence

👉 Implementation idea:

- Define allowed import graph:

```json
{
  "UI": ["Domain"],
  "Domain": [],
  "Infrastructure": ["Domain"]
}
```

- Parse `ImportDeclSyntax`
- Map files → modules/layers
- Validate edges

---

### **“Forbidden type usage across layers”**

Example:

- `URLSession` used outside networking layer

👉 Detect:

- `IdentifierTypeSyntax` matching forbidden symbols
- scoped by file path/module

---

# **3) Data integrity / domain invariants (your biggest differentiator)**

This is where your tool becomes _unique_.

### **🔴 Category C: Semantic invariants**

Example rules:

### **“No floating point for money”**

Detect:

```swift
Double
Float
```

in files matching:

- `Payment`
- `Invoice`
- etc.

---

### **“ID types must not be raw String”**

Detect:

```swift
let userId: String
```

Encourage:

```swift
struct UserID: RawRepresentable
```

👉 These are simple AST checks but **massively valuable**.

---

# **4) Error handling quality (AI is weak here)**

### **🔴 Category D: Weak error handling**

### **“Empty catch blocks”**

```swift
catch {
}
```

### **“Catch without logging or propagation”**

Detect catch blocks that:

- don’t rethrow
- don’t log
- don’t return error state

---

### **“Overly broad try?”**

```swift
try? criticalOperation()
```

Flag when:

- return value is ignored
- or in non-test code

---

# **5) Test quality coupling (this is advanced but powerful)**

### **🔴 Category E: Code ↔ test alignment**

This is where you go beyond typical linters.

### **“New public API without tests”**

Detect:

- `public func` added
- no corresponding test file change

This requires:

- diff awareness (CI integration)
- file matching heuristics

---

### **“Branch added without test delta”**

Harder, but even a simple version works:

- Count `if/switch` additions
- Compare test file changes

---

# **6) “AI smell” heuristics (this is your edge)**

These are subtle but very relevant.

### **🔴 Category F: Suspicious patterns**

### **“Overly generic naming”**

- `data`, `result`, `value`, `manager`

### **“Long functions with no comments”**

- AI often generates large blocks without explanation

### **“Missing edge case handling”**

Heuristic:

- function has conditionals
- but no:
    - `else`
    - or error path

---

# **7) Implementation strategy (important)**

Don’t try to solve everything with perfect analysis.

### **Start with:**

- **Shallow AST + heuristics**
- Not full type checking

SwiftSyntax is great for:

- structure
- patterns
- lightweight rules

Avoid:

- full data flow engine (too heavy early)

---

# 

# **8) Rule design: make them**

**adoptable**

This is critical.

Each rule should have:

### **✅ 1. Clear intent**

Bad:

Avoid X

Good:

Prevent silent data corruption in financial calculations

---

### **✅ 2. Escape hatch**

Allow:

```swift
// swiftprojectlint:disable:NoFloatingMoney
```

---

### **✅ 3. Severity levels**

- warning
- error
- critical

---

# **9) Suggested MVP rule set (if I were you)**

If you shipped just this, it would already be strong:

### **Core 10 rules:**

1. Fire-and-forget Task
2. Missing cancellation checks
3. Empty catch
4. Catch without handling
5. try? on non-trivial calls
6. Layer import violations
7. Forbidden types (e.g. Double for money)
8. Raw String IDs
9. Public API without tests (basic version)
10. Long function without comment

That’s a _very high signal_ set.

---

# **10) The bigger picture**

If you execute this well, your tool becomes:

A way to encode “things that would otherwise live in senior engineers’ heads”

That’s incredibly valuable—especially with AI in the loop.

---

If you want, next step I can:

- sketch a **SwiftSyntax rule implementation** (real code)
- or help you design a **rule DSL** so users don’t have to write Swift to define rules

Both are pivotal depending on how far you want to take this.