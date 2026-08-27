---
name: other-pr-code-review
description: Review a pull request for high-confidence defects without modifying code, then prepare or submit a request-changes review with exact implementation and test guidance.
---

# Pull Request Review Workflow

Use this skill for pull-request reviews where the PR author owns all code changes, including author handoffs and submitted **Request changes** reviews.

## Review procedure

1. Invoke and follow the personal `code-review` skill as the authoritative review procedure. Reuse its scope, defect criteria, evidence requirements, data-handling rules, and module-customization detection pass; do not duplicate or weaken them here.
2. Additionally, treat newly introduced C# 6+ language features in `Tireweb Sites\Web\` C# or inline server-side C# as high-confidence compatibility defects. This includes string interpolation, null-conditional access, `nameof`, expression-bodied members, and auto-property initializers; that path must remain compatible with C# 5.
3. Review only the pull-request diff and its directly relevant code paths. Do not modify workspace code, apply fixes, commit, push, install dependencies, or change the branch. The PR author owns all code changes.
4. Keep the review focused on findings confirmed by the `code-review` procedure. Omit style preferences, speculative concerns, and pre-existing defects.

## Reporting and PR submission

For each confirmed finding, provide a concrete code-change suggestion in this format:

````markdown
## Code change suggestions

1. **Imperative, outcome-focused title**
   `repo\relative\first-file`
   `repo\relative\second-file`
   `repo\relative\customizer-file`

   Explain the failure and why the proposed change preserves the default behavior.

   ### C#
   ```csharp
   // first-file
   // Show the exact interface, contract, or declaration change.
   ```

   ```csharp
   // second-file
   // Show the exact guarded logic or implementation change.
   ```

   ```csharp
   // customizer-file
   // Show the explicit opt-in configuration at the owning invocation.
   ```

   **Suggested test coverage:** Concrete user-visible or API scenario that proves the fix and confirms unaffected callers retain their current behavior.
````

- Use an outcome-focused title such as **Make alternate radial/bias inventory opt-in**. List every affected file directly below the title. For a multi-file fix, include a separate language-labelled code block for each file, with the file name in a short comment above its exact change. Prefer concise, directly applicable snippets over prose-only implementation steps.
- Include exact file paths, the failure mode, an explanation of the behavior-safe default, and observable test coverage for every finding. Use inline annotations only for findings on changed PR lines; otherwise use the review body.
- Submit a GitHub review only when the user explicitly asks. For blocking findings, submit **Request changes** with the complete handoff and test coverage using `gh pr review <number> --request-changes`.
- If no high-confidence findings remain, report the review as clean. Approve only when the user explicitly asks.
