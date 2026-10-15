# Published skills

This directory contains the team's published GitHub Copilot skills. Each skill
is installed from its own directory and must contain a `SKILL.md` file.

| Skill | Description |
| --- | --- |
| `backup-staging-files` | Back up an explicit list of Ezytire staging files to a persisted local directory before deployment, reusing deploy-files-staging SFTP settings and credentials. |
| `deploy-code-review` | Launch a coordinated, read-only nested code-review session using GPT-5.6 Sol, medium reasoning, and long context. Use when the user asks to delegate, run, or perform a code review in a nested session or reviewer sub-session while carrying forward review context and instructions from the main session. |
| `deploy-developer` | Create a nested developer session configured with GPT-5.6 Luna, maximum reasoning effort, and the 1.1M long-context setting. Use when the user asks to create, start, launch, deploy, or spin up a nested developer session. |
| `deploy-files-staging` | Deploy a user-supplied list of Ezytire web files and rebuilt project DLLs to staging through SFTP, with optional generation of the list from a git log expression. |
| `dev-testing` | Using a configured Playwright mcp to optimize and speed up the testing process and lower the tokens cost. Consolidated Ezytire developer testing, browser validation, staging verification, form-submission, and test-validation guidance. Invoke for requests involving development testing, validation, browser checks, staging verification, form testing, performance analysis, or Lighthouse.|
| `pr-with-review` | Create a pull request using the Ezytire title convention. Use when the user asks to create a PR from the current branch. |
| `qa-smoke-testing` | Author, execute, and maintain reusable QA smoke-test scenarios for website functionality affected by code changes. Use when QA needs to confirm that existing functionality still works as expected after a deployment or change. Can also convert existing QA steps written on natural speaking language, then the skill will convert it to test script after the inital run. |
| `staging-deployment` | Safely deploy Ezytire web files to staging through SFTP, including uncommitted changes, committed branch changes, or parent-authorized manifest assets. Use when asked to deploy, upload, or preview changes on staging. |
| `test-prod-by-pr` | Verify that one or more approved, merged GitHub pull requests have reached their user-specified production websites. Use when asked to test, validate, or confirm production deployments from PRs. |
| `website-styling-audit` | Delegate every audit, rerun, or repackage to one nested local chat worker using GPT-5.6 Luna with maximum reasoning and long context, then write a self-contained frontend-developer-ready report.html plus supporting local evidence files for CSS-driven responsive styling, layout, typography, color and contrast, component consistency, UI states, overflow, and accessibility-related styling signals. |

## Website styling audit prerequisites

The parent session performs a prerequisite preflight before it creates the
nested worker or allows navigation, full baseline-evidence reads, or bundle
output. During preflight the parent may read only the canonical root metadata
allowed by the skill contract for folder-only mode recovery. The worker must
be a nested local chat child configured with model `gpt-5.6-luna`, reasoning
effort `max`, and context tier `long_context` (the 1.1M context setting). It
does not need a project, branch, worktree, or repository checkout. The parent
passes the target URLs/routes, CSS scope, viewport/state requirements, output
base and label, baseline/rerun mode, preflight results, safety limits, and
expected local bundle path in the kickoff prompt. The worker performs the
audit itself and must not create another audit session.

A live audit requires the Playwright MCP browser capability set and a working
browser runtime. Every run that writes the canonical bundle requires Python
3.8 or newer, a local process runner, and an existing writable output
directory. Repackaging an existing audit bundle does not need a browser;
source-only runs record rendered checks as blocked.

The skill never installs software or dependencies implicitly. If Python,
Playwright, its browser runtime, a process runner, or a writable destination
is missing, it reports the exact blocker and gives installation or remediation
guidance before stopping. If nested-session creation or the exact requested
model/context settings are unavailable, it reports delegation as blocked and
does not silently use another model, create a project session, or execute
directly. See the skill's `Delegated execution boundary` and `First-run
prerequisite preflight` sections for the handoff, authentication, and supported
fallback boundaries.
