---
name: other-pr-code-review
description: Review a pull request for high-confidence defects without modifying code, then prepare or submit a request-changes review with exact implementation and test guidance.
---

# Pull Request Review Workflow

Use this skill for pull-request reviews where the PR author owns all code changes, including author handoffs and submitted **Request changes** reviews.

## Scope and operating constraints

- Report only high-confidence defects introduced by the pull request: correctness regressions, security issues, null-safety failures, broken user flows, and unsafe data handling. Exclude style preferences, speculative concerns, and pre-existing defects.
- Inspect locally: read the PR change overview, then inspect focused per-file diffs against the merge base.
- Treat values from requests, query strings, cookies, forms, databases, and external services as untrusted unless proven otherwise.
- Do not modify workspace code, apply fixes, commit, push, install dependencies, or change the branch. The PR author owns all code changes.

## Compatibility constraints

- All C# and inline server-side C# under `Tireweb Sites\Web\` must remain compatible with C# 5. Do not propose, introduce, or accept language features introduced in C# 6 or later.
- Treat a newly introduced C# 6+ feature in that path as a high-confidence compatibility defect. Examples include string interpolation, null-conditional access, `nameof`, expression-bodied members, and auto-property initializers.

## Module Customization and Offer-Markup Patterns

- For a reusable module whose new behavior varies by site or page, verify that the change is opt-in through an `IModule...` property and `ModuleData.AddModuleDependency(...)` at the customizer invocation. Treat a new site-configuration check inside the generic module as suspect when the caller can configure the behavior instead.
- When an `IModule...` contract changes, verify the interface, the control implementation, and every `GetModuleWithID(..., moduleNumber, ...)` invocation path. Intended callers must opt in explicitly and unconfigured consumers must retain a safe default.
- When a reusable helper builds or configures a component whose behavior varies by caller, verify that it accepts the value as a parameter and forwards it unchanged to the component's configuration mechanism (for example, `AddModuleDependency`). Flag a hard-coded context-dependent value inside the helper; fixed invariants are not a finding.
- Treat any value originating from a request, query string, cookie, form, session, database, or external service as untrusted unless its provenance is proven. For any such value rendered in an `.ascx` attribute, require `System.Web.HttpUtility.HtmlAttributeEncode()` and inspect every skin/template that renders the same shared value.

### Required Detection Pass for Site-Specific Module Logic

When a PR changes a reusable module control, treat a direct branch on site- or customizer-specific state as a **potential module-customization defect requiring validation**. Triggers include `Configuration.Is...(...)`, `SiteKind`, `WebSiteID`, `SiteContext`, a customizer type/name, or a site-specific page/URL condition. The predicate being functionally correct is not sufficient: configuration ownership, not the predicate result, is the concern.

For every trigger:

1. Locate the module's `IModule...` contract and all `GetModuleWithID(..., moduleNumber, ...)` / `GetModule(...)` invocation paths.
2. Determine whether an existing dependency expresses the behavior. Otherwise, validate that the behavior should be represented by an explicitly named opt-in property with a safe default (normally `false`) on the interface and control.
3. Verify that the owning customizer sets the property through `AddModuleDependency(...)` at every intended invocation and that unconfigured callers retain the default.
4. If the diff and call paths prove the behavior is site-specific in a reusable module, report it as a high-confidence finding. Cite the exact module line containing the predicate and every customizer invocation path that must be updated. Do not dismiss it merely because the current customizer appears to be the only known caller.

## Evidence and validation

- Validate every finding before reporting it. For localized logic, trace the changed control and data flow from the triggering input or state through the failure, then cite the relevant paths, methods, and changed lines.
- For a changed core utility, shared service, or public contract with many callers, validate the contract at its immediate boundary instead of exhaustively tracing every caller. Provide a bounded, high-level impact justification with representative caller or interface evidence when useful, and state the affected scope and assumptions.
- Ensure a proposed fix preserves intended behavior and uses current, safe project conventions where appropriate. Do not treat intentional modernization as a defect solely because it diverges from nearby legacy code; flag it only for a concrete regression or incompatible inconsistency.
- Report only defects supported by diff and code-path evidence. Omit hypotheses that depend on unknown configuration, data, or runtime behavior unless the PR proves that dependency.
- Run focused non-mutating checks when useful: `git diff --check`, static searches, JavaScript syntax checks, existing tests, or the narrowest existing build/test. State the evidence used and any exact blocker. Missing dependencies, outputs, or unrelated baseline failures are validation limitations, not PR defects, unless introduced by the PR.

## Reporting and PR submission

For each confirmed finding, provide this handoff:

```markdown
## Review fixes to apply

1. **Short defect title**
   `repo\relative\path`
   Explain the failure, identify the exact expression or method to change, and provide a minimal replacement snippet or implementation step.

## Suggested review/test coverage

1. Concrete user-visible or API scenario that proves the fix.
```

- Include an exact file path, failure mode, and observable test coverage for every finding. Use inline annotations only for findings on changed PR lines; otherwise use the review body.
- Submit a GitHub review only when the user explicitly asks. For blocking findings, submit **Request changes** with the complete handoff and test coverage using `gh pr review <number> --request-changes`.
- If no high-confidence findings remain, report the review as clean. Approve only when the user explicitly asks.
