---
name: website-styling-audit
description: Audit live websites, recover existing audit folders for reruns or repackaging, and always write a frontend-developer-ready report.html plus supporting local evidence files after an unslop wording pass. Before any audit action or local output, verify the available browser, Python, process, and filesystem capabilities and give installation guidance without installing anything implicitly. The scope is CSS-driven responsive styling, layout, typography, color and contrast, component consistency, UI states, overflow, and accessibility-related styling signals. If explicitly requested, reuse the local bundle for GitHub PR or CI publication. Note scripts or runtime causes only when they directly produce the styling issue.
---

# Website styling audit

Use this skill for a read-only, CSS-focused audit of a website's rendered
presentation. The goal is to find reproducible CSS and responsive-layout
defects, while keeping subjective design preferences separate from confirmed
issues. Do not modify the audited site, its source files, server state,
persistent browser storage, or user data unless the user explicitly asks for a
separate change.

CSS, stylesheets, computed styles, cascade/specificity, breakpoints, layout
geometry, and CSS-driven visual states are the primary scope. Inspect HTML,
JavaScript, network responses, fonts, images, or other runtime behavior only
when they are needed to explain a visible styling symptom. Do not turn a
general console error, functional defect, code-quality issue, or API failure
into an audit finding unless it directly causes the reported visual problem.
When a script is relevant, keep the finding about the styling impact and record
the script or runtime behavior as a contributing-cause note.

## First-run prerequisite preflight

Run this gate before asking for missing audit inputs, reading a baseline or
local project for audit evidence, opening a target, invoking browser
interactions, creating an output directory, or taking screenshots. Do not
start an audit or write local output while a required check is `Blocked` or
`Pending`.

The preflight has two phases:

1. Check host capabilities that do not depend on the user's target or output
   path. Do this without navigating to a website or creating audit files.
2. After the user supplies the required URL, baseline, project path, and
   output base, validate the mode-specific target and destination. Only then
   begin the audit workflow.

Report the result as a short status table with `PASS`, `BLOCKED`, or `PENDING`
for every item, including the detected executable/version or the exact
missing capability and remediation. A successful preflight is not evidence
that the target is accessible; target access is still recorded separately.
Copy the final preflight statuses, executable/version details, browser
initialization result, destination writability result, and any optional
fallback that was not used into the report's validation notes.

### Required capabilities for every run

- **A local process runner:** Use whatever local command/terminal capability
  the host exposes. Do not assume PowerShell, Bash, `cmd`, Node.js, `npm`,
  `npx`, or a project-specific runner exists. A process runner is required to
  execute the standard-library embedding step and the final bundle
  validation. If no process runner is available, stop and report that the
  audit cannot produce its required validated bundle.
- **Python 3.8 or newer:** Resolve a real interpreter before any audit output.
  On Windows, check `py -3 --version` and then `python --version`; on
  macOS/Linux, check `python3 --version` and then `python --version`. Accept
  only Python 3.8 or newer and record the executable path and version. The
  embedding and validation steps use only the Python standard library; do not
  substitute Python 2, a virtual environment that cannot be resolved again,
  Node.js, or an unverified third-party script.
- **Local filesystem access:** The host must be able to resolve paths,
  preserve the audit bundle structure, and read/write the user-selected
  destination. Do not create the final folder until the destination checks
  below pass.

### Mode-specific requirements

| Run mode | Required before navigation or output | Not required |
| --- | --- | --- |
| Initial live audit or live rerun | Playwright browser tools, a working browser runtime, Python 3.8+, a process runner, and a writable output base | Computer Use, DevTools, Node.js, and project-specific packages |
| Repackage without navigation | Python 3.8+, a process runner, filesystem access, and a writable output base | Playwright and any browser runtime; do not initialize a browser |
| Local source-context audit with no live URL | Python 3.8+, a process runner, filesystem access, and a writable output base | Playwright is optional, but all rendered checks must be recorded as blocked |

For an initial live audit or live rerun, verify that the host exposes the
minimum Playwright capability set needed by this skill:
`browser_navigate`, `browser_run_code_unsafe` or `browser_evaluate`,
`browser_snapshot`, `browser_resize`, and `browser_take_screenshot`. Discover
deferred or provider-specific tools before invoking them; do not guess a tool
name or silently replace the browser tool with an unrelated integration.
After the target URL is known, perform one minimal browser initialization
probe. If browser initialization reports a missing executable, unavailable
provider, or other setup error, retry once as described in [Tool guidance](#tool-guidance),
then stop the live audit and report the exact error. Do not treat an HTTP
response or a visible browser window as proof that the Playwright runtime is
ready.

### Output destination gate

After the prerequisite capability checks pass, ask for the base directory when
the user has not supplied one. Require an existing local directory, resolve
it to a canonical absolute path, and verify that it is writable before
creating the timestamped audit folder. A non-destructive writability probe may
create one uniquely named temporary file and remove it immediately; if cleanup
fails, treat the destination as blocked and do not create the audit bundle.
For a local project audit, apply the project-root restriction in
[Required inputs and scope](#required-inputs-and-scope) before writing.

### Missing prerequisite behavior and installation guidance

This skill never silently installs software, packages, browser binaries,
extensions, or project dependencies. Never run `pip install`, `npm install`,
`npx playwright install`, `winget`, `brew`, `apt`, or an equivalent
installation command as part of an audit. If a required capability is
missing, stop before navigation and output, report the exact blocked check,
and give the user an actionable remedy:

- For Python, ask the user to install an approved Python 3.8+ distribution
  from their organization's software source or the official Python
  distribution for their operating system, then verify that `py -3`,
  `python3`, or `python` resolves to Python 3.8+.
- For Playwright, ask the user to enable/install the Playwright MCP
  integration supported by their Copilot Desktop setup and ensure its
  managed browser runtime is installed using that integration's documented
  process. Do not download a browser or execute a browser-install command
  automatically.
- For a missing process runner or filesystem permission, ask the user to run
  the skill in a Copilot environment that exposes a local process and
  writable destination, or to choose an existing writable directory. Do not
  weaken the report contract to avoid this requirement.

If the user explicitly asks the agent to perform a separate installation,
request confirmation immediately before that installation, follow the
computer-use and environment safety rules, and rerun the complete preflight
after installation. Do not continue from a stale `PASS` result.

Computer Use or DevTools are optional fallbacks, not prerequisites for the
normal path. Never switch to them silently. Use an already-running,
user-visible browser only when the user explicitly requests the fallback and
the relevant tool is available; otherwise keep the live checks blocked and
report the missing Playwright capability. A fallback cannot justify installing
or launching undocumented software, bypassing a browser warning, or changing
the read-only safety boundary.

## Required inputs and scope

Use the URLs, routes, and constraints already supplied by the user. If a
required input is missing, ask for one item at a time:

1. Ask for one or more full `https://` or `http://` website URLs. Preserve the
   route for each URL and remove exact duplicates.
2. Ask for specific routes or page states only when the requested scope cannot
   be inferred from the supplied URLs. Do not crawl an entire site by default.
3. Ask for a local project path only when the user wants CSS/source context or
   no live URL is available. A local path is read-only context; it is not proof
   of the rendered result.

Before writing any local audit output, resolve these two values:

1. **Base directory.** If the user has not supplied one, ask where the audit
   should be saved. Require a local directory that exists and is writable,
   such as `C:\Website Audits`. Do not write the report, screenshots, or JSON
   files until the user supplies and the skill validates this destination. If
   the user declines, gives no usable path, or the path is not writable, stop
   before creating local files and state the blocker.
2. **Website and surface label.** Derive a readable label from the target
   host and route when they make the surface clear. Otherwise ask for one
   combined label, such as `Flynn's Tire And Auto Service - Home page` or
   `Flynn's Tire And Auto Service - Tire Page`. Preserve the user's spacing and
   capitalization. Replace only filesystem-invalid characters (`< > : " / \ |
   ? *` and control characters), trim trailing periods/spaces, and keep the
   readable words. Do not silently replace a useful label with a generic slug.

Ask these questions one at a time when either value is missing. Resolve and
validate both values before creating the destination folder.

Use `label` as the human-facing display label for each confirmed finding.
For an initial audit, format it as `Styling Issue - 1`, `Styling Issue - 2`,
and so on, assigned in final priority order. Keep the machine `id` separately
as `WS-001`, `WS-002`, and so on. On a rerun, preserve the existing label and
ID pair when the same finding is matched, even if priority order changes. The
numeric suffix is stable across reruns when the same finding is matched. New
findings receive the next unused numeric suffix.
Display the friendly label prominently in HTML and optional Markdown. Keep the
stable machine ID in secondary metadata, JSON, evidence maps, filenames,
annotation tokens, and cross-file references.

When an existing audit folder is the only supplied local destination, use its
canonical parent directory as the output base after validating that it exists
and is writable. Ask for a different base only when that parent is not
writable or the user requests another location.

For a local project audit, resolve both the audited project path and the
requested base directory to canonical absolute paths before writing. Resolve
existing symlinks or junctions and compare complete path segments, not string
prefixes. If the base directory is the project root or is below it, reject the
destination by default and ask for a sibling or outside directory. Write into
the source tree only after the user explicitly confirms that choice for this
audit. If the audit targets only a remote URL, there is no project-root
restriction, but the base directory must still exist and be writable.

## Existing audit folder input and run mode

Accept an existing audit output folder as an input. A valid audit folder has
`report.html` and `audit-files\findings.json` plus
`audit-files\evidence-map.json`. Treat it as a baseline and evidence bundle,
never as the audited website source and never as proof of the current live
state. Do not read its application source files, start a server from it, or
use its screenshots as current evidence.

Before deciding what work to do, read the folder in this order:

1. Parse `audit-files\findings.json` and
   `audit-files\evidence-map.json` as exact machine-readable values.
2. Read `report.html` for human-readable context and any fields absent from
   the JSON.
3. Verify that the files agree on the audit ID, surface label, targets,
   routes, timestamps, viewport matrix, states, finding IDs, occurrence IDs,
   finding labels, selectors/regions, measurements, recommendations, state-test
   matrix, evidence pairs, known blockers, and prior output layout.

Recover the target URL(s), route(s), surface label, source audit timestamp,
viewport matrix, states, finding IDs, selectors/regions, measurements,
recommendations, state-test matrix, evidence pairs, blockers, and output paths before asking for
information already present. Prefer JSON for exact values and use HTML as the
fallback. If a required field is missing or the sources conflict, ask one
focused question about that field instead of guessing.

The core baseline fields are target URL(s), route(s), surface label, source
audit timestamp, viewport matrix, states, finding IDs, occurrence/selector
data, finding labels, state-test matrix, and evidence-file mappings. Older folders may not have rerun metadata
such as `runType` or `comparisonStatus`; add those fields to the new output
after validating the core baseline, but do not invent a missing target,
viewport, state, finding, or evidence mapping.

When a folder is supplied without an explicit mode, ask one focused question:
"Should I rerun/recheck the live target and compare it with this baseline, or
repackage the existing evidence without navigating to the site?" Do not infer
the mode from the folder name alone.

Use this decision table:

| Input and instruction | Action |
| --- | --- |
| Existing audit folder + unambiguous live URL(s) + "rerun", "recheck", or "audit again" | Run a fresh read-only live audit using the recovered routes, states, and viewport matrix, then compare it with the baseline. Existing screenshots are not current evidence. |
| Existing audit folder + explicit "skip audit", "repackage", or equivalent | Do not navigate to the site. Produce a new handoff from the verified baseline evidence and state `runType: repackage`; never claim a rerun occurred. |
| Existing audit folder + rerun requested but no usable live URL | Ask for the live URL, or mark the rendered rerun blocked if the user cannot provide one. Do not infer a local project, server, or route. |
| Ordinary URL with no existing audit folder | Run a normal initial audit with `runType: initial`. |

For a repackage, preserve the baseline findings and evidence as
`Baseline only`, copy verified evidence into the new support folder when
needed for a self-contained handoff, and mark that no current-state
observation was made. Do not assign `Fixed`, `Still reproduces`, or `Regressed`
without a fresh live audit.

Use the resolved base directory and label to create the local destination
described in [Output routing and local bundle](#output-routing-and-local-bundle).
Keep the report and all supporting files in that one destination so it can be
moved or zipped as a unit.

When the user does not provide viewport requirements, audit each target across
this multi-size CSS viewport matrix. These are representative popular display
sizes, not exact device emulation or physical-pixel dimensions:

| Profile | Viewport | Purpose |
| --- | --- | --- |
| Narrow mobile | `320 x 568` | Small-phone wrapping and minimum-width check |
| Common Android mobile | `360 x 800` | Common narrow Android responsive breakpoint |
| Compact mobile | `375 x 667` | iPhone SE/8-class width and short viewport |
| Modern mobile | `390 x 844` | Common modern phone width |
| Large mobile | `412 x 915` | Large-phone width and long mobile content |
| Compact desktop | `1280 x 720` | Smaller laptop/desktop layout |
| Common laptop | `1366 x 768` | Common desktop browser width |
| Desktop | `1440 x 900` | Standard desktop layout |
| Wide desktop | `1920 x 1080` | Large-monitor max-width and whitespace check |

Use at least two mobile sizes and two desktop sizes for every audit by default,
and prefer the full matrix above when time and access allow. Do not reduce the
audit to one mobile and one desktop viewport unless the user explicitly limits
the scope; record that limitation. Add `768 x 1024` when tablet behavior, a
tablet breakpoint, or a portrait-oriented layout is in scope. Record the exact
CSS viewport dimensions actually checked in the report.

## Safety and non-goals

- Use read-only navigation and interactions. Do not submit orders, payments,
  bookings, account changes, administrative forms, or destructive actions.
- Do not request, receive, store, or enter credentials, MFA codes, API tokens,
  or other secrets. If authentication is required, navigate to the login
  screen, pause for the user to authenticate directly, and continue only after
  the user confirms that the session is ready.
- Do not bypass certificate, malware, unsafe-site, robots, access-control, or
  browser security warnings. Record the target as blocked instead.
- Do not inject permanent CSS, edit application files, install dependencies, or
  start an undocumented command. Temporary browser instrumentation such as
  freezing animations for deterministic inspection is allowed, but disclose it
  in the report.
- Do not report a JavaScript error, missing API response, or general functional
  failure by itself. Record it only when evidence ties it to a visible
  CSS/styling symptom, such as a required state class never being applied or a
  stylesheet failing to load.
- Do not claim that a site is fully accessible or fully conformant from a
  styling audit. Report only the accessibility-related styling signals that
  were actually checked.
- A successful HTTP response or a visually attractive screenshot is not proof
  that no issue exists. Tie every finding to a route, viewport, state, region,
  and observable evidence.

## Audit workflow

### 1. Build the target matrix

Create a small matrix containing the target URL, route, required state,
viewport, and audit status. Treat each URL/route and viewport pair as a
separate observation. Avoid duplicate checks only when the page, state, and
viewport are identical.

For a local project path:

1. Read the project's existing README, package manifest, and documented
   development commands to identify an already-supported local URL or route.
   Inspect relevant CSS/SCSS files, imports, design tokens, and component style
   conventions only as supporting evidence.
2. Reuse an existing running server when one is supplied or already available.
3. If no browser URL is available, report source-context findings separately
   and mark rendered visual checks as **Blocked**. Do not invent a server
   command or install packages just to perform this audit.
4. Compare source design tokens, styles, or component conventions with the
   rendered page only as supporting context. A source declaration alone is not
   evidence that the user sees it. Inspect scripts only when they directly
   control a CSS class, inline style, breakpoint state, or layout data involved
   in a visible issue.

### 2. Triage access and stability

Use Playwright browser tools (`playwright-browser_*`) by default. Navigate
directly to each supplied URL; do not infer production or staging hosts.

For each target:

- Record redirects, the final URL, and whether the page is actually
  accessible. Treat authentication, `401`/`403`, a blocked browser warning,
  an unavailable host, or an unrecoverable tool error as **Blocked**, not as a
  styling failure.
- Wait for the observable stable state needed for the check. Prefer a
  meaningful content or loading-state condition over arbitrary delays.
- Record dynamic or personalized content, feature flags, consent banners,
  geo-specific content, animation, or time-dependent data that can affect the
  observation.
- Inspect console output at `warning` or `error` level and network activity
  only when they help explain a broken visual result. Prioritize failed CSS,
  font, image, or other styling-related assets; inspect a script failure only
  when it directly controls the affected visual state. Separate third-party
  noise from application causes.
- Disable CSS transitions and animations only after the initial state is
  understood and only when motion prevents deterministic inspection. Note this
  temporary instrumentation.

If a login or MFA challenge appears, stop at that boundary. The user must
complete authentication in the same browser session; never ask for the secret
or attempt to bypass the challenge. If the user cannot authenticate, retain
the target as **Blocked** and state which checks were not covered.

### 3. Inspect visual regions at each viewport

At minimum, inspect the visible header/navigation, primary content or hero,
repeated content components, forms or controls that are visible without
mutation, and footer or other persistent regions. Use targeted accessibility
snapshots and DOM/computed-style probes, then use a screenshot when visual
evidence is needed.

Check the following categories:

#### Responsive layout and geometry

- Content remains within the viewport without unexplained horizontal
  scrolling, clipped text, off-screen controls, or overlapping fixed/sticky
  elements.
- Grid and flex layouts reflow at the supplied widths; columns do not collapse
  into unreadable widths; images, media, and containers preserve intended
  proportions.
- Navigation, dialogs, banners, cookie notices, and sticky controls do not
  cover primary content or trap focus visually.
- Breakpoint changes are coherent rather than leaving partially hidden,
  duplicated, or misaligned controls.
- Check both document overflow and the affected visible region. A horizontal
  scroller may be intentional; confirm whether the content is discoverable
  and usable before calling it a defect.

#### Typography and content fit

- Font family, size, weight, line height, letter spacing, and casing support
  the apparent hierarchy and remain legible at every viewport.
- Headings, labels, buttons, links, and body copy do not wrap, truncate, or
  collide unexpectedly. Distinguish intentional ellipsis from lost content.
- Compare repeated text roles for consistent type treatment and check that
  loading or fallback fonts do not visibly shift the layout.

#### Spacing and alignment

- Check container gutters, section rhythm, card padding, control gaps,
  baseline alignment, and vertical centering.
- Compare repeated components against each other rather than treating one
  unusual but intentional composition as a defect.
- Check alignment against the actual visible region and container boundaries,
  not just source markup order.

#### Color, contrast, and visual hierarchy

- Sample foreground/background pairs for body text, large text, links,
  buttons, placeholders, disabled text, borders, icons, and focus indicators.
- When measuring contrast, use the WCAG thresholds as signals: `4.5:1` for
  normal text, `3:1` for large text, and `3:1` for essential non-text UI
  components and focus indicators. Record the sampled colors and element
  context; do not generalize from one sample to the entire site.
- Check that states are not conveyed by color alone and that disabled or
  low-emphasis styling remains distinguishable from missing or broken content.

#### Component and visual-system consistency

- Compare repeated buttons, links, inputs, cards, alerts, badges, navigation
  items, icons, radii, borders, shadows, and spacing.
- Check default, hover, focus, expanded, selected, disabled, error, empty, and
  loading states when they can be exposed safely without submitting or
  mutating data.
- If JavaScript adds the class, attribute, inline style, or data that exposes a
  state, inspect only enough of that trigger to explain the CSS result. Report
  the missing or incorrect styling as the finding and list the script behavior
  as a contributing cause, not as a separate functional defect.
- Prefer an explicit design-system rule, repeated pattern, or user-provided
  reference when classifying inconsistency as a defect. Otherwise classify a
  taste or brand preference as a **Suggestion**.

#### Overflow and broken visual assets

- Look for missing images, broken icon fonts, unexpected fallback glyphs,
  failed font loads, empty boxes, layout shifts, and content clipped by
  `overflow: hidden`. Treat a missing asset as a styling finding only when the
  rendered impact is visible.
- Check controls at the smallest supplied width and at text-heavy or
  localized-looking content when present.
- Inspect relevant `4xx`/`5xx` stylesheet, font, image, or asset failures, but
  do not report a network failure as a styling issue unless it produces an
  observable visual problem.

#### Accessibility-related styling signals

- Move focus through visible controls with keyboard navigation and verify a
  clear focus indicator, sufficient contrast, and no focus ring clipped by
  overflow or a sticky container.
- Check that headings, labels, landmarks, link/button affordances, and error
  messages remain visually distinguishable and are not conveyed by color alone.
- Check likely touch targets and spacing for cramped controls. Record the
  measured size and whether the control is essential; do not claim complete
  WCAG compliance from a size heuristic.
- Use reduced-motion or high-contrast emulation when the issue or product
  requirement calls for it, and record the emulated setting.
- Use a targeted accessibility snapshot to support the visual observation.
  Accessibility-tree presence alone does not prove that the styling is usable.

### 4. Exercise safe UI states

State checks are CSS styling scenarios, not functional tests. A state is not
covered merely because its selector or CSS rule exists. Exercise it with a
user-reachable, read-only interaction, compare it with the same target's
default state, and record the result in `statesChecked`. Never place orders,
make payments or bookings, change accounts, submit forms, or mutate server
data. Do not require credentials to expose a state.

Use this reusable state-test matrix for every state you actually exercise:

| Field | Required value |
| --- | --- |
| Target URL/route | Exact URL and route |
| Viewport | Exact CSS width x height |
| Initial state | State before the trigger |
| Trigger | User action and locator/region |
| Resulting state | State after the trigger |
| Selectors/regions | Target and any affected overlay/message |
| Measurements | Default-vs-state computed styles and geometry |
| Evidence IDs | State-specific original/annotated IDs and filenames |
| Restoration | Restored, not restored, or not applicable, with reason |
| Audit outcome | Pass, confirmed CSS issue, Suggestion, Blocked, or untested |

Include each exercised state in `statesChecked`, including its route and
viewport. Include each unsafe, unavailable, or skipped state in
`blockedOrUntested` with the exact blocker. If a state-specific issue is
confirmed, give it a friendly `Styling Issue - N` label and a stable `WS-*`
machine ID. Annotate only that confirmed issue.

#### Hover

- Use Playwright locator hover or pointer movement on user-reachable links,
  buttons, cards, navigation items, and other controls.
- Capture the default state first, then compare hover versus default computed
  `color`, `background-color`, `border`, `box-shadow`, `text-decoration`,
  geometry, and any text wrapping or layout shift.
- Capture the hover screenshot with a state slug such as `hover`, then move the
  pointer away and confirm the target returns to its prior state.
- Do not use a hover-only CSS rule as proof when no user-reachable target can
  be located. Mark it untested or Blocked.

#### Focus

- Use keyboard `Tab` and `Shift+Tab` on visible controls. Do not inject a
  focus class or call a synthetic focus event as evidence.
- Record `:focus`/`:focus-visible`, outline, box-shadow, color, contrast,
  clipping, and whether the indicator remains visible at mobile and desktop
  viewports.
- Check that focus is not hidden behind overflow, sticky UI, or an overlay.
  This is a styling signal only, not a claim of full accessibility
  conformance.

#### Selected or active

- Safely select a non-mutating tab, filter, navigation item, or option.
- Compare selected and unselected computed styles, geometry, text treatment,
  and indicators. Use `aria-selected`, `aria-current`, or a state class only
  as supporting evidence after observing the user-visible state.
- Restore the prior selection when possible. Do not submit or trigger a
  server-side change just to expose a selected style.

#### Expanded or collapsed

- Open and close reversible menus, disclosures, accordions, tooltips, and
  dialogs with ordinary user actions. Capture both states.
- Check `aria-expanded`/`hidden` as supporting evidence, then inspect
  visibility, geometry, overflow, z-index, overlay coverage, focus placement,
  and close behavior.
- Restore the collapsed/closed state when possible. Do not submit a form or
  mutate server data.

#### Validation error

- Expose an empty or invalid state only through a documented client-only/demo
  path or a safe interaction that cannot submit data, navigate, mutate server
  state, or require credentials.
- Check error border, background, text, icon, message placement, label
  association as a visual signal, focus/scroll behavior, contrast, wrapping,
  layout shift, and clipping.
- Never force a hidden error state by editing application state or firing
  synthetic events. If the state cannot be reached safely, mark it
  Blocked/untested and state the exact blocker.

For every state, capture state-specific evidence with a state slug in the
evidence ID and filename, for example
`EV-WS-001-01-checkout-390x844-hover-original.png`. Keep the stable finding ID
unchanged across states and reruns. A state issue is confirmed only after the
default-vs-state comparison shows an observable CSS difference that violates
the expected behavior or supplied design rule.

### 5. Capture evidence

Use DOM/accessibility snapshots and targeted computed-style or geometry
measurements as the primary evidence. Use screenshots for a representative
baseline, a confirmed visual defect, or a comparison that cannot be conveyed
reliably in text.

For each screenshot:

- capture the exact URL/route, viewport, state, and timestamp;
- name or label the evidence so it maps to a finding;
- capture the smallest useful region when possible, plus enough surrounding
  context to identify the problem;
- avoid exposing credentials, tokens, personal data, or private page content;
- do not edit the screenshot to hide a defect. If sensitive content makes a
  screenshot unsafe, use a DOM measurement or report that the visual evidence
  was withheld.

### Screenshot annotations

Capture original screenshots for representative tested states and preserve
those files. For every confirmed visual issue, create a separate annotated
copy. Do not annotate a **Suggestion** as a confirmed defect.

1. Capture a viewport-only screenshot in the same stable state used for the
   finding. Before or immediately after capture, record
   `window.innerWidth`, `window.innerHeight`, `window.devicePixelRatio`, the
   screenshot bitmap width and height, and any clip origin.
2. Measure the affected element with its exact
   `getBoundingClientRect()` or Playwright locator bounding box. Do not use
   guessed coordinates, document coordinates, or a measurement from a
   different viewport or state. Do not scroll between measurement and capture.
3. Map CSS pixels to bitmap pixels. For a viewport screenshot, use
   `scaleX = bitmapWidth / innerWidth` and
   `scaleY = bitmapHeight / innerHeight`, then multiply the rectangle's
   viewport-relative `x`, `y`, `width`, and `height` by those scales. If the
   screenshot is clipped, subtract the clip origin before scaling. Account for
   `devicePixelRatio`; do not assume it is `1`.
4. On the copy, draw a non-destructive circle or box around the affected
   region, a numbered marker and arrow outside the defect, and a short
   `Styling Issue - N` label that does not cover the evidence. Include the
   stable `WS-*` ID as secondary text when space allows. Keep computed-style,
   geometry, and contrast measurements in the report even when the screenshot
   does not prove a cascade or contrast issue by itself.
5. Use stable names containing the evidence ID, finding ID, and CSS viewport,
   for example
   `EV-WS-001-01-checkout-390x844-default-annotated.png` and
   `EV-WS-001-02-checkout-390x844-default-original.png`. Normalize route text
   for filenames and keep the original and annotated files paired. Keep both
   PNG files unchanged under `audit-files\screenshots\...`; the HTML embedding
   step creates data URIs without replacing or moving the archived evidence.

Add an evidence map to the report and local bundle. Every annotated file must
identify its finding ID, URL/route, viewport/state, selector or visible region,
and measurement.

### 6. Classify and prioritize findings

Classify every item as one of:

- **Confirmed CSS issue**: reproducible at a stated URL/route, viewport, and
  state, with evidence of a CSS declaration, cascade, computed-style, layout,
  breakpoint, or other measurable styling problem.
- **Confirmed styling issue with a contributing cause**: the visible problem is
  confirmed as above, but a script, markup state, failed stylesheet/font/image,
  or other runtime behavior directly explains why the CSS result occurs. Keep
  the finding focused on the styling impact and identify the cause separately.
- **Suggestion**: a subjective or preference-based improvement without enough
  evidence to call it a defect. State the design rationale and do not imply
  that it violates a requirement.
- **Blocked / untested**: the check could not be performed because of access,
  instability, missing state, unavailable local URL, or tool limitations.

Use this priority order:

| Priority | Use for |
| --- | --- |
| `P0` | A styling failure prevents access to essential content or controls across a supported viewport, or makes the interface effectively unusable. |
| `P1` | Major overlap, clipping, unreadable text, broken responsive layout, or a high-impact focus/contrast problem on an important route. |
| `P2` | A repeated or meaningful inconsistency, moderate spacing/typography issue, or a narrower viewport/state defect with a practical workaround. |
| `P3` | Minor polish issue with limited impact, or a low-frequency edge case. |
| `Suggestion` | Subjective design, brand, or refinement recommendation. |

Within the same priority, order findings by user impact, number of affected
routes/components, reproducibility, and confidence. Do not inflate severity
because an issue is visually noticeable if users can still read and operate
the affected control.

## Required report content

Build one complete, concise, prioritized audit record even when no issues are
found. `report.html` is the canonical human-facing output for the frontend
developer who will fix the CSS. The developer must not need to open Markdown or
JSON to understand or fix the findings. Render all of the content below into
`report.html`; `findings.json` and `evidence-map.json` remain supporting
machine-readable handoff files.

Write `report.html` as a valid, self-contained HTML document. Do not put a
Markdown heading, table, or image syntax in the HTML file. Use this structure
as the content contract:

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Website styling audit: {surface label}</title>
</head>
<body>
  <main class="audit-report" data-audit-id="{auditId}">
    <header>
      <h1>Website styling audit</h1>
      <p>Surface: {surface label}</p>
      <p>Audit ID: {auditId}</p>
      <p>Run type: {initial, rerun, or repackage}</p>
      <p>Audit timestamp: {ISO 8601 timestamp}</p>
    </header>

    <section id="summary">
      <h2>Summary</h2>
      <p>{overall result and highest-impact pattern}</p>
    </section>

    <section id="coverage">
      <h2>Coverage</h2>
      <p>Targets and routes: {URLs/routes}</p>
      <p>CSS viewports checked: {exact width x height matrix}</p>
      <p>States checked: {states}</p>
      <p>Coverage limits: {none or exact reduction and reason}</p>
    </section>

    <section id="state-tests">
      <h2>State tests</h2>
      <article data-state-test="hover">
        <h3>Hover</h3>
        <p>Target URL/route: {URL and route}</p>
        <p>Viewport: {width x height}</p>
        <p>Initial state: default</p>
        <p>Trigger: {locator or visible region and pointer action}</p>
        <p>Resulting state: hover</p>
        <p>Selectors/regions: {target and affected region}</p>
        <p>Measurements: {default-vs-state computed styles and geometry}</p>
        <p>Evidence IDs: {state-specific IDs}</p>
        <p>Restoration: {restored or exact limitation}</p>
        <p>Audit outcome: {Pass, confirmed issue, Suggestion, Blocked, or untested}</p>
      </article>
    </section>

    <section id="comparison" data-comparison-status="{not applicable, compared, or not run}">
      <h2>Baseline comparison</h2>
      <p>Baseline folder: {path or not applicable}</p>
      <p>Baseline audit ID/timestamp: {values or not applicable}</p>
      <p>Current audit timestamp: {value}</p>
      <p>Coverage changes: {recovered coverage and exact scope changes}</p>
      <article id="WS-001-comparison" data-finding-id="WS-001"
               data-finding-label="Styling Issue - 1">
        <h3>Styling Issue - 1: {title}</h3>
        <p>Stable finding ID: WS-001</p>
        <p>Status: {Fixed, Still reproduces, Regressed, Not verified, or Baseline only}</p>
        <p>Developer action: {Fix, Verify, or Leave alone}</p>
        <p>Previous measurements/evidence: {values and embedded baseline images when shown}</p>
        <p>Current measurements/evidence: {values and embedded current images}</p>
      </article>
      <p>New findings: {Styling Issue labels with stable IDs, or none}</p>
    </section>

    <section id="findings">
      <h2>Findings</h2>
      <article id="WS-001" data-finding-id="WS-001"
               data-finding-label="Styling Issue - 1" data-priority="P1"
               data-classification="Confirmed CSS issue">
        <h3>Styling Issue - 1: {concise title}</h3>
        <p>Stable finding ID: WS-001</p>
        <p>Priority: P1</p>
        <p>Classification: Confirmed CSS issue</p>
        <p>Confidence: {confidence}</p>
        <p>Recommendation: {fix guidance}</p>

        <section id="WS-001-O01" data-finding-id="WS-001" class="finding-occurrence">
          <h4>Occurrence for Styling Issue - 1</h4>
          <p>Stable occurrence ID: WS-001-O01</p>
          <p>URL/route: {URL and route}</p>
          <p>Viewport/state: {width x height and state}</p>
          <p>Trigger: {user action and locator/region}</p>
          <p>Selector/region: {selector or visible region}</p>
          <p>Expected: {expected result}</p>
          <p>Observed: {observed result}</p>
          <p>CSS/computed-style evidence: {measurements}</p>
          <p>Evidence IDs: EV-WS-001-01 (annotated), EV-WS-001-02 (original)</p>
          <figure>
            <img data-audit-image-id="EV-WS-001-01"
                 data-audit-image-kind="annotated"
                 src="__AUDIT_IMAGE__EV-WS-001-01__"
                 alt="Styling Issue - 1 (WS-001), header nav at 390 x 844 in the default state">
            <figcaption>
              Annotated evidence.
              <a data-audit-image-id="EV-WS-001-02"
                 data-audit-image-kind="original"
                 href="__AUDIT_IMAGE__EV-WS-001-02__">Open original</a>
            </figcaption>
          </figure>
        </section>
      </article>
    </section>

    <section id="contributing-causes">
      <h2>Contributing causes</h2>
      <p>{Only scripts, assets, or runtime behavior that directly cause a styling issue}</p>
    </section>

    <section id="suggestions">
      <h2>Suggestions</h2>
      <p>{Subjective improvements. Do not create annotated defect images for these}</p>
    </section>

    <section id="evidence-map">
      <h2>Evidence map</h2>
      <p>{Evidence ID, stable finding ID, Styling Issue label,
         occurrence ID, URL/route, viewport/state, selector/region,
         measurement, and embedded original/annotated evidence}</p>
    </section>

    <section id="blocked-or-untested">
      <h2>Blocked or untested</h2>
      <p>{Target, check, and exact blocker or limitation}</p>
    </section>

    <section id="validation">
      <h2>Validation notes</h2>
      <p>{Authentication, dynamic content, instrumentation, browser/tool
         outcomes, and post-write bundle validation}</p>
    </section>
  </main>
</body>
</html>
```

If a Markdown export is explicitly requested, write it as the optional
`report.md` beside `report.html`. It is not the canonical output and must not
replace the HTML report.

### Self-contained HTML image embedding

The finalized `report.html` is the canonical shareable artifact. It must open
from any folder, email attachment, or file preview and render every annotated
screenshot without `audit-files` beside it and without a web server. Keep the
original and annotated PNGs unchanged under
`audit-files\screenshots\original\` and `audit-files\screenshots\annotated\`
for archive, validation, and JSON evidence maps. Sharing only `report.html`
preserves the visual evidence, but not the machine-readable JSON handoff.
Keep report styling inline or semantic. Do not add a required external
stylesheet, font, script, or other resource dependency.

Build the HTML from a technical/template source first. Keep that source
outside the final surface folder or remove it after successful embedding. Use
explicit tokens, not guessed paths or broad string replacement:

```html
<img data-audit-image-id="EV-WS-001-01"
     data-audit-image-kind="annotated"
     src="__AUDIT_IMAGE__EV-WS-001-01__"
     alt="Styling Issue - 1 (WS-001), header nav at 390 x 844 in the default state">
<a data-audit-image-id="EV-WS-001-02"
   data-audit-image-kind="original"
   href="__AUDIT_IMAGE__EV-WS-001-02__">Open original</a>
```

The token ID must resolve to an `original` or `annotated` item in the
validated current `evidence-map.json`. Every annotated evidence item shown in
the map must have exactly one annotated token. If an original-image link is
shown, it must have its own original token and be embedded too. Preserve the
alt text and finding, occurrence, and evidence IDs.

Run a Python 3 step using only the standard library after the technical source
is complete and before the final bundle validation. The script must:

- load `audit-files\evidence-map.json`, reject duplicate or missing evidence
  IDs, and require every annotated item to be represented by a token;
- resolve each token only to a local `file` under the current
  `audit-files\screenshots\` tree. Reject absolute paths, path traversal,
  missing files, unsupported image types, and files outside the validated
  bundle. Do not embed JSON, selectors, URLs, credentials, CSS, scripts, or
  arbitrary external resources;
- use an explicit image MIME map, such as `.png: image/png`, and encode the
  unchanged bytes as `data:image/png;base64,...`;
- replace each exact token once, fail on duplicate or unknown tokens, and fail
  if any token remains unresolved;
- preserve the original HTML attributes and write only the finalized
  `report.html`.

This is a minimal implementation pattern. It intentionally supports PNG
screenshots only; add another format only with a matching dimension decoder.

```python
from html.parser import HTMLParser
from pathlib import Path
import base64
import binascii
import json
import struct
import sys

MIME_BY_SUFFIX = {".png": "image/png"}
TOKEN_PREFIX = "__AUDIT_IMAGE__"

def fail(message):
    raise SystemExit(f"embed-audit-images: {message}")

def inside(path, root):
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False

def png_dimensions(raw, evidence_id):
    if raw[:8] != b"\x89PNG\r\n\x1a\n" or len(raw) < 24:
        fail(f"{evidence_id} is not a valid PNG")
    return struct.unpack(">II", raw[16:24])

class AttributeReader(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.elements = []

    def handle_starttag(self, tag, attrs):
        self.elements.append((tag, dict(attrs)))

surface = Path(sys.argv[1]).resolve()
template = Path(sys.argv[2]).resolve()
report = (surface / "report.html").resolve()
map_file = (surface / "audit-files" / "evidence-map.json").resolve()
bundle = (surface / "audit-files").resolve()
screenshots = (bundle / "screenshots").resolve()

if not template.is_file() or not map_file.is_file():
    fail("template or evidence-map.json is missing")

data = json.loads(map_file.read_text(encoding="utf-8"))
items = data.get("items")
if not isinstance(items, list):
    fail("evidence-map.json.items must be an array")

by_id = {}
embedded = {}
for item in items:
    evidence_id = item.get("evidenceId")
    if not evidence_id or evidence_id in by_id:
        fail(f"duplicate or missing evidence ID: {evidence_id!r}")
    by_id[evidence_id] = item
    if item.get("kind") not in {"original", "annotated"}:
        continue

    relative_file = Path(item.get("file", ""))
    if relative_file.is_absolute():
        fail(f"{evidence_id} uses an absolute file path")
    image = (surface / relative_file).resolve()
    if not inside(image, screenshots) or not image.is_file():
        fail(f"{evidence_id} is outside the screenshot bundle or missing")
    mime = MIME_BY_SUFFIX.get(image.suffix.lower())
    if mime is None:
        fail(f"{evidence_id} has an unsupported image type")

    raw = image.read_bytes()
    width, height = png_dimensions(raw, evidence_id)
    expected = item.get("measurement", {}).get("screenshot", {})
    if (width, height) != (expected.get("width"), expected.get("height")):
        fail(f"{evidence_id} dimensions do not match evidence-map metadata")
    embedded[evidence_id] = {
        "uri": f"data:{mime};base64,{base64.b64encode(raw).decode('ascii')}",
        "mime": mime,
        "dimensions": (width, height),
    }

source = template.read_text(encoding="utf-8")
tokens = []
remaining = source
while TOKEN_PREFIX in remaining:
    _, tail = remaining.split(TOKEN_PREFIX, 1)
    if "__" not in tail:
        fail("malformed image token")
    evidence_id, remaining = tail.split("__", 1)
    token = f"{TOKEN_PREFIX}{evidence_id}__"
    if evidence_id in tokens:
        fail(f"duplicate image token: {evidence_id}")
    if evidence_id not in embedded:
        fail(f"image token has no local evidence item: {evidence_id}")
    tokens.append(evidence_id)

for evidence_id, item in by_id.items():
    if item.get("kind") == "annotated" and evidence_id not in tokens:
        fail(f"annotated evidence has no HTML token: {evidence_id}")

rendered = source
for evidence_id in tokens:
    token = f"{TOKEN_PREFIX}{evidence_id}__"
    rendered = rendered.replace(token, embedded[evidence_id]["uri"], 1)
if TOKEN_PREFIX in rendered:
    fail("unresolved image token remains")

def validate_data_uri(value, evidence_id):
    try:
        prefix, payload = value.split(",", 1)
        expected = embedded[evidence_id]
        if prefix != f"data:{expected['mime']};base64":
            fail(f"{evidence_id} has the wrong image MIME type")
        decoded = base64.b64decode(payload, validate=True)
        if png_dimensions(decoded, evidence_id) != expected["dimensions"]:
            fail(f"{evidence_id} decoded dimensions do not match metadata")
    except (ValueError, binascii.Error) as error:
        fail(f"{evidence_id} has invalid base64 data: {error}")

reader = AttributeReader()
reader.feed(rendered)
for tag, attrs in reader.elements:
    evidence_id = attrs.get("data-audit-image-id")
    if tag == "img":
        if evidence_id not in embedded:
            fail("img is missing a valid data-audit-image-id")
        if by_id[evidence_id].get("kind") != "annotated":
            fail(f"{evidence_id} is not annotated evidence for an img")
        validate_data_uri(attrs.get("src", ""), evidence_id)
    if attrs.get("data-audit-image-kind") == "original":
        if evidence_id not in embedded:
            fail("original link is missing a valid data-audit-image-id")
        if by_id[evidence_id].get("kind") != "original":
            fail(f"{evidence_id} is not original evidence for an original link")
        validate_data_uri(attrs.get("href", ""), evidence_id)

for evidence_id in tokens:
    if embedded[evidence_id]["uri"] not in rendered:
        fail(f"embedded URI is missing: {evidence_id}")

report.write_text(rendered, encoding="utf-8", newline="\n")
```

The exact-token checks above are intentional. They prevent a missing evidence
ID from silently producing a broken report while avoiding brittle replacement
of unrelated HTML text.

Every confirmed finding must include an ID, priority, classification, confidence,
and one or more occurrence records. Each occurrence must include the URL or
route, viewport, state, selector or visible region, expected versus observed
behavior, CSS/computed-style or screenshot evidence, measurements, evidence
IDs, and a concrete recommendation.
Use the friendly `label` (`Styling Issue - N`) as the prominent human-facing
heading. Keep the stable `id` (`WS-001`) in secondary metadata and all
machine/evidence references.
Include a confidence level when the evidence is sampled or affected by dynamic
content. Add a contributing-cause note only when a script, asset, markup state,
or runtime behavior directly affects the styling. If no confirmed issue was
found, say **No confirmed CSS styling issues in the checked coverage** rather
than claiming the site has no styling issues.

## Output routing and local bundle

Always create and validate a local artifact bundle. It is the only default
output. `report.html` is the single canonical human-facing report. Markdown is
not required.

After the base directory and website/surface label are resolved, create this
destination:

```text
<user-base-directory>\<website> - <specific surface>\
  report.html
  audit-files\
    findings.json
    evidence-map.json
    screenshots\
      original\
      annotated\
```

The `<website> - <specific surface>` folder is the sanitized human-readable
label from the input step. For an initial audit, use that label as the folder
name when it does not exist. If any run's destination already exists, create an
additional timestamped sibling such as
`<website> - <specific surface> - 20261012-093620\` and keep the prior folder
untouched. For a rerun or repackage, always use that timestamped sibling. If
the supplied baseline folder already has a suffix matching
` - YYYYMMDD-HHmmss`, remove that suffix before deriving the unsuffixed
surface label and creating the next sibling. Do not overwrite an existing
report folder by default. Only ask for replacement confirmation when the user
explicitly requests replacing it, and ask immediately before writing.
Report the final absolute destination path.

Create the destination and its subfolders only after the user supplied a
writable base directory and the collision behavior is resolved. Do not install
a package or require a project-specific runner. Keep all report links
relative where they are intentionally support-file links, but never use a
relative image `src` or original-image `href` in the finalized HTML. Keep
`report.html` and `audit-files` together so the full bundle can be moved or
zipped without repairs.

If the HTML includes JSON or other support-file links, label them as optional
support for the full bundle and state that they are unavailable when only the
standalone HTML file is shared. They must never be required to render the
findings or images.

The embedding step may make `report.html` large. That is expected. A copy of
`report.html` alone preserves the visual handoff; the `audit-files` folder is
still required when the developer needs JSON mappings, measurements, or the
unchanged original/annotated PNG archive.

Every audit bundle must have this structure, even when there are no confirmed
issues. Keep `audit-files\screenshots\annotated\` empty when no confirmed
visual issue was found.

### Post-write local bundle validation

After writing the files, validate the bundle before reporting it as complete.
Use the surface folder as the validation root and require this exact structure:

```text
<surface-folder>\
  report.html
  audit-files\
    findings.json
    evidence-map.json
    screenshots\
      original\
      annotated\
```

An explicitly requested `report.md` may be an additional sibling, but it does
not replace any required path. The validator must:

1. Confirm every required file and directory exists and that no required path
   was redirected outside the surface folder.
2. Parse both JSON files as UTF-8 JSON. Check every required root field listed
   in the machine-readable schema, verify that finding IDs, occurrence IDs,
   and evidence IDs are present and unique, and reject malformed or duplicate
   IDs. For a `rerun` or `repackage`, also require the baseline metadata,
   `runType`, `currentAuditTimestamp`, `comparisonStatus`,
   `previousFindingId`, previous/current measurements, current evidence IDs,
   finding labels, comparison statuses, and `stateTests`. Confirm each `label`
   matches its stable ID suffix (`WS-001` -> `Styling Issue - 1`) and each
   state test has a trigger, default-vs-state measurement, evidence IDs,
   restoration status, and outcome.
3. Parse the finalized `report.html` after the Python embedding step. Require
   every `img[src]` and every anchor marked
   `data-audit-image-kind="original"` to use a `data:image/<type>;base64,...`
   URI. Reject relative screenshot paths, `audit-files` image paths, unresolved
   image tokens, and unsupported MIME types. Normal external target links and
   intentionally documented support-file links may remain, but the report must
   render its images without them.
4. Resolve every `file`, `originalFile`, and `annotatedFile` in
   `evidence-map.json` relative to the surface folder. Require each mapped
   file to exist, each issue evidence item to reference a valid finding and
   occurrence, each `findingLabel` to match the finding's stable ID/label pair,
   and each occurrence `evidenceIds` entry to resolve to exactly one map item.
5. Require every `kind: "annotated"` item to have an existing paired original
   file. Permit annotated evidence only when its finding classification is
   `Confirmed CSS issue` or `Confirmed styling issue with a contributing cause`.
   Suggestions may link originals or measurement evidence, but must not have
   annotated items or annotated image links.
6. Check that each confirmed annotated image and its original use the stable
   evidence ID and viewport filename, and that the CSS rectangle, bitmap
   rectangle, screenshot dimensions, `devicePixelRatio`, scale factors, and
   clip origin are present for screenshot measurements.
7. For a rerun, verify that every prior finding ID appears in the comparison
   data, even when it is `Fixed`, `Not verified`, or `Baseline only`, and that
   every current finding is either matched to a prior ID or assigned a new ID
   after the prior maximum. For a repackage, verify that all findings are
   `Baseline only` and that no current-state claim or fresh-live evidence is
   presented.
8. Verify that every baseline evidence link is relative, resolves only when
   the baseline is a known sibling folder, and never contains an absolute path,
   URL, or broken target.
9. Verify every expected embedded image data URI. Base64-decode it, confirm its
   MIME type matches the validated local evidence file, and compare its decoded
   PNG dimensions with `measurement.screenshot.width` and
   `measurement.screenshot.height` in `evidence-map.json`. Confirm that no
   `__AUDIT_IMAGE__...__` token remains anywhere in the final HTML.

If any check fails, report the exact file, field, path, or ID that failed and
the reason. Do not claim the audit bundle is complete until the failure is
fixed and the validation passes.

### Local report requirements

Run the unslop wording pass before writing `report.html` or any optional
Markdown export. Keep a technical source copy until the prose file is written,
then compare the result with the source. Preserve every URL, route, viewport,
selector, finding ID, severity, classification, confidence level, measurement,
evidence filename, recommendation, and validation note. Never apply unslop to
JSON or rewrite selectors, numeric measurements, IDs, URLs, or filenames.

`report.html` must contain:

- the audit timestamp, target URLs/routes, exact CSS viewport matrix actually
  checked, states checked, and any coverage reduction;
- the run type (`initial`, `rerun`, or `repackage`) and audit ID;
- the reusable state-test matrix for every exercised state, including target
  URL/route, viewport, initial state, trigger, resulting state,
  selectors/regions, default-vs-state measurements, evidence IDs,
  restoration status, and outcome. State names not actually exercised must
  not be presented as covered;
- prioritized findings with severity, classification, and confidence, with an
  friendly display label and stable machine ID, plus an occurrence block for
  every URL/route, viewport, state, selector or visible
  region, expected versus observed behavior, CSS/computed-style measurements,
  recommendation, and direct evidence references;
- for `rerun` and `repackage`, a baseline comparison section with the baseline
  folder/path and audit timestamp, recovered versus current coverage, every
  prior finding's comparison status, developer action (`Fix`, `Verify`, or
  `Leave alone`), previous/current measurements, embedded evidence, and new
  findings;
- validation notes covering authentication, dynamic content, temporary
  instrumentation, blocked checks, and tool outcomes;
- an evidence map where every evidence item has its evidence ID, finding ID,
  finding label, occurrence ID, URL/route, viewport/state, selector or region,
  measurement, current evidence IDs, and valid baseline provenance when
  available.

In `report.html`, put each finding in its own `article` or equivalent block
with the friendly display label prominently and the stable finding ID in
secondary metadata, followed by facts, measurements, recommendation, and
evidence references. For each confirmed visual issue, render the annotated
image next to the finding and provide an embedded data-URI link to the
original. The template may use `__AUDIT_IMAGE__<evidence-id>__` placeholders,
but the finalized HTML must contain `data:image/...;base64,...` in every
report image `src` and original-image `href`. Do not make report rendering
depend on `audit-files`, a relative screenshot path, or a web server. Include
alt text that names the finding, region, viewport, and state. Keep the
CSS/computed-style evidence in text when an image cannot prove a cascade or
contrast measurement by itself.

Do not create `report.md` by default. Generate it only when the user
explicitly requests a Markdown export or a downstream tool requires it. If
created, save it beside `report.html`, apply the same unslop and fact-preserving
checks, and keep it an optional export rather than the primary handoff.
Apply the same unslop pass to any Markdown prose, GitHub PR comment, or CI
annotation written from this audit. Never unslop JSON, image files, selectors,
numeric measurements, IDs, URLs, or filenames.

### Machine-readable handoff files

Write standard UTF-8 JSON with no new dependency. These files must be usable to republish the audit to an explicitly requested
GitHub PR or CI artifact later.

`findings.json` must contain:

- root fields `schemaVersion`, `auditId`, `generatedAt`,
  `currentAuditTimestamp`, `runType` (`initial`, `rerun`, or `repackage`),
  `comparisonStatus`, `baseline` (`auditId`, `path`, and `timestamp` when
  present), `targets`, `surfaceLabel`, `reportFile` (`report.html`),
  `supportRoot` (`audit-files`), `viewportMatrix`, `statesChecked`,
  `stateTests`, `findings`, `blockedOrUntested`, and `validation`;
- each finding's `id`, `priority`, `classification`, `confidence`, `title`,
  `label` (`Styling Issue - N`), `recommendation`, `comparisonStatus`,
  `developerAction`, `previousFindingId`, `previousFindingLabel`,
  `previousMeasurements`, `currentMeasurements`, `currentEvidenceIds`,
  `occurrences`, and optional `contributingCause`;
- each `occurrences[]` item must contain `occurrenceId`, `url`, `route`,
  `viewport` (`width` and `height`), `state`, `selector`, `region`,
  `trigger`, `expected`, `observed`, `cssEvidence`, `measurements`,
  `recommendation`, `evidenceIds`, and `restoration`;
- each `stateTests[]` item must contain `state`, `url`, `route`, `viewport`,
  `initialState`, `trigger`, `resultingState`, `selectorsOrRegions`,
  `measurements`, `evidenceIds`, `restoration`, and `outcome`;
- `validation` fields for authentication/dynamic-content limits,
  instrumentation, browser/tool results, and output routing status.

`evidence-map.json` must contain root fields `schemaVersion`, `auditId`, and
`surfaceLabel`, `reportFile` (`report.html`), `supportRoot` (`audit-files`),
`runType`, `currentAuditTimestamp`, `baselineAuditId` (or `null`), and
`items`. Each item must include `evidenceId`, `findingId` (or `null` for a
baseline), `occurrenceId` (or `null` for a baseline), `kind` (`original`,
`annotated`, or `measurement`), `file`, `url`, `route`, `viewport`, `state`,
`selectorOrRegion`, `measurement`, and `capturedAt`. Issue evidence must use a
valid current occurrence ID. Each non-baseline item must also include
`findingLabel` (`Styling Issue - N`); baseline items use `null`. A comparison
item may include
`baselineEvidenceId` and `baselineFile`; only use `baselineFile` when it is a
valid relative path to a known sibling baseline folder, otherwise set it to
`null` and keep the baseline reference in the report text. For screenshots,
`measurement` must contain `cssRect`, `bitmapRect`, and a `screenshot` object
with `width`, `height`, `devicePixelRatio`, `scaleX`, `scaleY`, and
`clipOrigin`. Keep the exact same IDs and filenames in both JSON files, the
HTML report, and any optional Markdown export. The HTML report embeds the
image bytes; these JSON file paths remain archive/machine-handoff metadata.

Store `file`, `originalFile`, `annotatedFile`, and `baselineFile` paths
relative to the current output folder, using the `audit-files/` prefix for
current files. Do not store absolute local paths in link fields. The
`baseline.path` provenance field may retain the resolved baseline folder path,
but it is metadata only and must never be used as an HTML link or file path.

Use a stable mapping:

- finding IDs are `WS-001`, `WS-002`, and so on, assigned once in report
  priority order;
- finding labels are `Styling Issue - 1`, `Styling Issue - 2`, and so on. The
  label number is assigned from the machine ID's numeric suffix and remains
  paired with that ID across reruns;
- matched prior findings keep their existing finding ID. New findings receive
  IDs after the highest prior numeric ID, ordered by current priority;
- occurrence IDs are `WS-001-O01`, `WS-001-O02`, and so on, assigned in
  viewport/state observation order within each finding;
- evidence IDs are `EV-<finding-id>-<NN>` for issue evidence, with `NN` as a
  two-digit counter incremented for every evidence item for that finding
  across all occurrences. Baseline evidence uses `EV-BASE-<NN>`, with the
  counter incremented across all baselines. On a rerun or repackage, seed each
  counter from the baseline and continue it so current evidence IDs cannot
  collide with prior evidence IDs;
- filenames are
  `{evidenceId}-{route-slug}-{width}x{height}-{state-slug}-{original|annotated}.png`.
For state tests, the `{state-slug}` is required and must match the state
recorded in `stateTests` and `statesChecked` (for example `hover`, `focus`,
`selected`, `expanded`, or `validation-error`).

For example:

```text
EV-WS-001-01-checkout-390x844-default-annotated.png
EV-WS-001-02-checkout-390x844-default-original.png
EV-WS-001-03-checkout-1366x768-default-annotated.png
EV-BASE-01-home-1440x900-default-original.png
```

Keep the original and annotated files paired. Annotate only confirmed issues.
Use the exact `getBoundingClientRect()` or locator coordinates and the CSS to
bitmap scaling rules from the screenshot workflow above. Preserve
`devicePixelRatio`, screenshot dimensions, clip origin, and the resulting
bitmap rectangle in `evidence-map.json`. Put each evidence ID in exactly one
occurrence's `evidenceIds` array, except baseline IDs, which have no finding
or occurrence.

For `rerun`, compare prior findings by stable finding ID when the recovered
route, selector/region, and occurrence key match. Otherwise use the recovered
route plus selector/region and title as the matching key. If a match is
ambiguous, keep the prior finding as `Not verified` instead of silently
renaming or deleting it. Use these comparison statuses:

| Status | Meaning | Developer action |
| --- | --- | --- |
| `Fixed` | The prior issue was covered by the current audit and no longer reproduces. | `Leave alone` |
| `Still reproduces` | The prior issue is covered and remains observable. | `Fix` |
| `Regressed` | A previously fixed or non-reproducing prior issue is observable again. | `Fix` |
| `Not verified` | The current run could not safely cover or resolve the prior issue. | `Verify` |
| `Baseline only` | No current-state observation was made, including every prior finding in a repackage. | `Verify` |
| `New` | A current confirmed issue has no matching prior finding. | `Fix` |

Never delete a prior finding because it is absent from the current result. Keep
its ID and mark it `Fixed`, `Not verified`, or `Baseline only` as appropriate.

### Output routing

1. Always finish and validate the local bundle first.
2. Stop after the local bundle and report its path. This skill does not create
   external work items or upload evidence by default.
3. If an explicit GitHub PR or CI publication is requested and the context
   supports it, the local bundle may be uploaded as a GitHub artifact or
   linked in a PR comment. GitHub publication is optional, never mandatory,
   and must not replace the local bundle.
4. If the requested GitHub publication is unavailable or fails, keep the local
   bundle, state the exact blocked step and error, and never claim the upload
   succeeded.

## Baseline rerun comparison workflow

For a `rerun`, use the recovered route, state, and viewport matrix as the
starting coverage. Record any user-requested additions or exclusions as exact
scope changes. Navigate to the live URL and collect new DOM/computed-style
measurements and new screenshots. Never reuse a baseline screenshot as current
evidence. Compare after the fresh audit, then write the current report and
support files into the new timestamped sibling.

For each prior finding:

1. Match the prior stable ID using the schema's stable matching rules.
2. Preserve the prior ID, its `Styling Issue - N` label, and occurrence
   details.
3. Record the comparison status, developer action, previous measurements and
   evidence links, current measurements and evidence IDs, and any scope
   limitation.
4. Keep a prior finding in the new report even when it no longer reproduces.
   A covered, non-reproducing issue is `Fixed`; an uncovered or inconclusive
   issue is `Not verified`.

For a `repackage`, read and validate the baseline only. Do not navigate,
resize a live page, or claim current measurements. Copy verified baseline
screenshots into the new `audit-files` tree when a self-contained package is
needed, assign non-colliding current-run evidence IDs, and label every prior
finding `Baseline only` with developer action `Verify`. Set the comparison
status to `not-run` and state plainly in the HTML report that no rerun
occurred.

## Tool guidance

- Use Playwright browser tools first:
  `playwright-browser_navigate`, `playwright-browser_run_code_unsafe`,
  `playwright-browser_snapshot`, `playwright-browser_evaluate`,
  `playwright-browser_resize`, `playwright-browser_emulate_media`, and
  `playwright-browser_take_screenshot` as appropriate.
- Batch viewport setup, navigation, waits, and targeted measurements with
  `playwright-browser_run_code_unsafe` when that reduces round trips. Prefer
  stable DOM conditions over arbitrary sleeps.
- Use `playwright-browser_console_messages` and
  `playwright-browser_network_requests` only for relevant warnings/errors or
  stylesheet, font, image, and other asset failures. Inspect script failures
  only when they directly explain a styling symptom. Do not include request or
  response payloads unless they are necessary to diagnose a visual failure.
- Use Computer Use only when a visible native browser or webview cannot be
  reached through Playwright. Follow its background-first interaction and
  authentication rules; do not use shell or window-manager workarounds to
  control the UI.
- Do not silently switch tools after a browser initialization failure. Retry
  once, then report the exact blocked coverage.

## Usage examples

- `Audit https://example.com for CSS styling issues at desktop and mobile widths.`
- `Audit these routes for responsive layout, typography, contrast, and focus styling: https://example.com/, https://example.com/catalog.`
- `Audit https://example.com/checkout for hover, focus, selected, expanded/collapsed, and validation-error styling where each state can be reached safely. Compare every exercised state with default, record blocked states, and use state slugs in the evidence filenames.`
- `Audit C:\Projects\storefront using its existing local URL, compare the shared header and button CSS across the supplied routes, and note any script that directly causes a visual mismatch.`
- `Review https://example.com/checkout without submitting anything; report confirmed CSS issues separately from subjective polish suggestions and only mention scripts when they explain the styling.`
- `Audit https://example.com/catalog. When prompted, use base directory \`C:\Website Audits\` and surface label \`Flynn's Tire And Auto Service - Home page\`. Open or share \`C:\Website Audits\Flynn's Tire And Auto Service - Home page\report.html\`; it is self-contained for visual review, while \`audit-files\` retains JSON mappings and unchanged PNG evidence for later GitHub or CI publication.`
- `Re-run the audit using C:\ESP\website audits\Flynn's Tire And Auto Service - Home page as the baseline. Recheck the live target after the fixes, use the recovered viewport matrix, compare every prior finding, and save an additional timestamped report under C:\ESP\website audits.`
- `Repackage C:\ESP\website audits\Flynn's Tire And Auto Service - Home page without navigating to the website. Produce a new timestamped handoff from the verified baseline evidence and mark every finding Baseline only.`
- `If you only provide an existing audit folder, ask whether to rerun/recheck the live target or repackage the existing evidence. Do not choose for the user.`
