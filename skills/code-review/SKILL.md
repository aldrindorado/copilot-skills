---
name: code-review
description: Review workspace or pull-request changes for high-confidence security, null-safety, SQL error-handling, and regression defects. Use for code-review and /review tasks.
---

# Code Review Guidance

## Review Output

### Inline Finding Location

For a GitHub pull-request review, post each actionable finding as an **inline review comment** anchored to the exact added or modified line that requires the change. Use the pull-request review-comment tool rather than only describing the finding in a summary. Select the line that introduces the defect; do not anchor the comment to a nearby method declaration, unrelated context, or a whole-file summary. If the defect spans multiple changed lines, use an inline range when supported; otherwise anchor to the most directly responsible changed line.

If a finding concerns unchanged code that is affected by the pull request, anchor it to the closest changed line that caused the regression and clearly identify the affected unchanged code in the comment. Do not report a standalone finding when it cannot be meaningfully tied to the pull-request diff.

For every reported finding, include an implementation-ready **Suggested change** preview in a fenced code block. Keep the preview narrowly scoped to the finding, show enough surrounding context to identify the edit, and use `-`/`+` lines when a replacement is clearer. Do not include a preview when no finding is reported.

Present findings as a numbered list with a spelled-out severity label, matching this format: `1. Critical — concise finding title`. Use only `Critical`, `High`, `Medium`, or `Low`; do not use priority shorthand such as `P0` or `P1`. Put the explanation beneath the finding title, followed by the suggested change preview and any essential remediation guidance.

## Verified Safe Exceptions - Do Not Flag

**`<%= %>` for trusted numeric IDs only**  
Do not flag unencoded `<%= %>` in HTML attributes only when the value is demonstrably a server-generated numeric ID (for example, `data-appointment-id`, `data-retailer-id`, `data-date-picker-id`, or `data-comments-id`). Continue to flag values that may contain user input, query-string values, database text, external API data, or any non-numeric string.

## High-Priority Issues to Always Catch

- **XSS via unencoded user input in HTML attributes**: Any `.ascx` expression writing user-supplied text (Notes, Comments, names, addresses) into an HTML attribute must be attribute-encoded. For eligible Web Forms data-binding expressions (`<%# ... %>`) that render a plain attribute value, prefer `<%#: ... %>` because it encodes the bound value. Use `System.Web.HttpUtility.HtmlAttributeEncode(...)` for `<%= ... %>` expressions or whenever `<%#:` is not valid for the expression, target framework, or intended output. Do not replace an expression that intentionally emits trusted markup, JavaScript, or a complete URL without first confirming that encoding preserves the required behavior.
- **DOM XSS via `innerHTML` in JavaScript**: Flag any changed `.js` code that writes dynamic or externally-derived values into `innerHTML` (including string concatenation or template literals), especially values sourced from `data-*` attributes, API responses, query-string data, cookies, or database-backed content. Prefer safe DOM construction (`document.createElement`, `createTextNode`, `textContent`, `setAttribute`) or sanitized/strictly trusted HTML only when a trusted-markup contract is explicitly documented.
- **Missing `return` after null/empty guard**: If a null or empty check logs an error but does not `return`, execution falls through into code that dereferences the null. Verify that the guard terminates the method.
- **Nullable operation results**: When a method result is null-checked before one member access, verify every subsequent branch also guards the result before accessing its members or collections (for example, `.Errors`, `.ID`, `.Success`).
- **Unhandled exceptions in SQL blocks**: New `SqlConnection`/`SqlCommand` blocks must follow the existing `try/catch/finally` pattern used throughout `DataAccess/`: catch into a local `Exception` variable, log via `ScratchPad.Current.Messages.Add()`, and close the connection in `finally`.

## JavaScript Declaration Review

- **Block-scoped declarations in changed code**: For every new or modified JavaScript declaration in a `.js` diff or JavaScript embedded in a server-side string literal, require `const` by default and `let` only when the binding is reassigned. Flag `var` unless function-scoped behavior or local compatibility requirements demonstrably require it. Review only changed code; do not request repository-wide declaration-only rewrites.
- **Top-level constant naming**: In changed JavaScript files, require module/file-scope constants to use `UPPER_SNAKE_CASE` (for example, `REVIEW_LIMIT`, `MAPS_WAIT_TIMEOUT_MS`, `MAX_DISTANCE_METERS`). Flag lowerCamelCase names for top-level constants unless they are established external API contracts that cannot be changed safely.

## Validation Scope

- **Do not build `Tireweb Sites.sln`**: Never build the full `Tireweb Sites\Tireweb Sites.sln` solution for syntax validation, dependency checks, or code review testing. Build the smallest affected project instead; for site business changes, `Tireweb Sites\Sites\Sites.csproj` is an acceptable targeted build. Prefer narrower existing tests, syntax checks, or project builds whenever they cover the changed code.

## Module Customization and Offer-Markup Patterns

- **Keep site-specific behavior at the module invocation**: When a reusable module needs behavior that varies by site or page, expose an opt-in property on its `IModule...` contract, implement it with a safe default, and set it through `ModuleData.AddModuleDependency(...)` in the customizer. Do not make the reusable module infer customizer-specific behavior from the current site configuration.
- **Trace contract changes through every invocation path**: For a new `IModule...` property, verify the interface and control implementation agree, then inspect all `GetModuleWithID(..., moduleNumber, ...)` paths. Intended callers must explicitly opt in; callers that do not configure the behavior must retain the safe default.
- **Forward caller-controlled configuration**: When a reusable helper builds or configures a component whose behavior varies by caller, accept that value as a parameter and pass it unchanged to the component's configuration mechanism (for example, `AddModuleDependency`). Do not hard-code context-dependent values inside the helper; fixed invariants are allowed.
- **Audit every skin that renders a shared value**: Treat any value originating from a request, query string, cookie, form, session, database, or external service as untrusted unless its provenance is proven. When such a value is rendered in an `.ascx` attribute, use `<%#: ... %>` for eligible data-binding expressions or `System.Web.HttpUtility.HtmlAttributeEncode(...)` otherwise, and inspect every skin/template that renders the same value, not only the default skin.

### Required Detection Pass for Site-Specific Module Logic

When a diff changes a reusable module control, automatically flag a **potential module-customization issue** if the module directly branches on site- or customizer-specific state, including `Configuration.Is...(...)`, `SiteKind`, `WebSiteID`, `SiteContext`, a customizer type/name, or a site-specific page/URL condition. Do this even when the condition is functionally correct; configuration ownership, not the predicate result, is the concern.

For every such potential issue:

1. Locate the module's `IModule...` contract and all `GetModuleWithID(..., moduleNumber, ...)` / `GetModule(...)` invocation paths.
2. Check whether an existing dependency already expresses the behavior. Otherwise, recommend an explicitly named opt-in property with a safe default (normally `false`) on the interface and control.
3. Require the owning customizer to set that property with `AddModuleDependency(...)` at every intended invocation, while unconfigured callers retain the default.
4. Report the exact module line containing the site predicate and the customizer invocation paths that must be updated. Do not dismiss the finding merely because the current customizer happens to be the only known caller.
