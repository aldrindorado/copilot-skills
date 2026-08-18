# Fowler-Inspired Code-Smell Heuristics

Use these as optional design prompts only after the primary code-review process
finds no actionable issue. They are adapted as concise review heuristics from
the code-smell concepts popularized by Martin Fowler; they are not rules.
Repository conventions and automated tooling take precedence.

For each candidate, ask whether it is introduced or materially worsened by the
changed code. Prefer leaving a clean, proportionate small change alone.

| Heuristic | Look for in the diff | Possible refactoring direction |
| --- | --- | --- |
| Mysterious Name | A name hides its purpose, value, or business meaning. | Rename for the role it plays; if that remains unclear, simplify the design first. |
| Duplicated Code | New code repeats the same meaningful logic shape in another changed location. | Extract a shared operation when the duplication is stable and genuinely equivalent. |
| Feature Envy | A method works mainly with another object's data or behavior. | Move behavior toward the object that owns the data, where that improves cohesion. |
| Data Clumps | The same related values repeatedly travel together. | Introduce a small value object or parameter object with a clear domain purpose. |
| Primitive Obsession | A primitive represents a recurring domain concept with important rules. | Model that concept with a focused type or validated abstraction. |
| Repeated Conditionals | The change adds the same decision tree in more than one place. | Centralize the decision or use a strategy/map when it improves clarity. |
| Shotgun Surgery | A small behavior change requires coordinated edits in many distant modules. | Gather related behavior behind a more cohesive boundary. |
| Divergent Change | One edited module gains responsibilities for unrelated reasons. | Separate responsibilities when they are likely to change independently. |
| Speculative Generality | The change adds hooks, options, or abstraction without a current use. | Remove the unused flexibility and retain the simplest implementation for today. |
| Message Chains | A caller navigates through several objects to get work done. | Hide the traversal behind an operation on the nearest appropriate object. |
| Middle Man | A new layer adds little beyond forwarding calls. | Remove or enrich the layer when it has no meaningful policy or boundary role. |
| Refused Bequest | A subtype or implementation must ignore much of its inherited contract. | Prefer composition or a narrower contract that matches its actual behavior. |
