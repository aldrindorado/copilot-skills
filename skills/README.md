# Published skills

This directory contains the team's published GitHub Copilot skills. Each skill
is installed from its own directory and must contain a `SKILL.md` file.

| Skill | Description |
| --- | --- |
| `backup-staging-files` | Back up an explicit list of Ezytire staging files to a persisted local directory before deployment, reusing deploy-files-staging SFTP settings and credentials. |
| `checkout-origin-branch` | Safely connect the current Copilot-managed worktree to a user-specified origin branch. |
| `deploy-code-review` | Launch a coordinated, read-only nested code-review session using GPT-5.6 Sol, medium reasoning, and long context. Use when the user asks to delegate, run, or perform a code review in a nested session or reviewer sub-session while carrying forward review context and instructions from the main session. |
| `deploy-developer` | Create a nested developer session configured with GPT-5.6 Luna, maximum reasoning effort, and the 1.1M long-context setting. Use when the user asks to create, start, launch, deploy, or spin up a nested developer session. |
| `deploy-files-staging` | Deploy a user-supplied list of Ezytire web files and rebuilt project DLLs to staging through SFTP, with optional generation of the list from a git log expression. |
| `dev-testing` | Using a configured Playwright mcp to optimize and speed up the testing process and lower the tokens cost. Consolidated Ezytire developer testing, browser validation, staging verification, form-submission, and test-validation guidance. Invoke for requests involving development testing, validation, browser checks, staging verification, form testing, performance analysis, or Lighthouse.|
| `pr-with-review` | Create a pull request using the Ezytire title convention. Use when the user asks to create a PR from the current branch. |
| `qa-smoke-testing` | Author, execute, and maintain reusable QA smoke-test scenarios for website functionality affected by code changes. Use when QA needs to confirm that existing functionality still works as expected after a deployment or change. Can also convert existing QA steps written on natural speaking language, then the skill will convert it to test script after the inital run. |
| `staging-deployment` | Safely deploy Ezytire web files to staging through SFTP, including uncommitted changes, committed branch changes, or parent-authorized manifest assets. Use when asked to deploy, upload, or preview changes on staging. |
| `test-prod-by-pr` | Verify that one or more approved, merged GitHub pull requests have reached their user-specified production websites. Use when asked to test, validate, or confirm production deployments from PRs. |
| `website-styling-audit` | Delegate every audit, rerun, or repackage to one nested local chat worker using GPT-5.6 Luna with maximum reasoning and long context, then write a self-contained frontend-developer-ready report.html plus supporting local evidence files for CSS-driven responsive styling, layout, typography, color and contrast, component consistency, UI states, overflow, and accessibility-related styling signals. |

## Team setup

### Install one skill

Install only the staging deployment skill:

```powershell
npx skills add aldrindorado/copilot-skills@staging-deployment -g -y
```

`@staging-deployment` installs only `skills/staging-deployment`.

### Install the website styling audit skill

Install only the website audit skill:

```powershell
npx skills add aldrindorado/copilot-skills@website-styling-audit -g -y
```

`@website-styling-audit` installs only `skills/website-styling-audit`. Every
audit, rerun, or repackage is delegated to one nested local chat worker with no
project or repository checkout. The invoking session performs only the
prerequisite preflight and kickoff handoff. The worker must use
`gpt-5.6-luna` with `max` reasoning and `long_context` (the 1.1M context
setting). Live audits require a working Playwright MCP browser capability and
Python 3.8 or newer for the standard-library report embedding and validation
steps. The skill checks these requirements before navigation or local output
and never installs them implicitly. Repackaging an existing audit bundle
without navigation does not require a browser, but it still uses the nested
chat worker. If nested-chat creation or any requested worker setting is
unavailable, the skill reports the limitation and does not fall back to a
project session or direct execution.

### Install all published skills

Install every skill under this repository's `skills` directory:

```powershell
npx skills add aldrindorado/copilot-skills -g -y
```

### Legacy PowerShell installer

1. Ask a repository administrator to invite you as a collaborator.
2. Clone this repository to any local directory:

   ```powershell
   git clone https://github.com/aldrindorado/copilot-skills.git "$HOME\source\copilot-skills"
   ```

3. Install its skills into the local Copilot directory:

   ```powershell
   Set-Location "$HOME\source\copilot-skills"
   .\scripts\Install-CopilotSkills.ps1
   ```

4. Restart GitHub Copilot Desktop if the new skills do not appear immediately.

The installer refuses to overwrite an existing non-repository skill. To update
skills previously installed by this repository, pull the latest changes and
run:

```powershell
git pull
.\scripts\Install-CopilotSkills.ps1 -Force
```

If `npx` is unavailable, use the legacy PowerShell installer on Windows or the
installation method supported by your Copilot Desktop environment. After
installing or updating a skill, restart GitHub Copilot Desktop if it does not
appear immediately.

Shared GitHub Copilot skills for the team
