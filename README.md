# Shared Copilot Skills

This public repository is the team's source of truth for shareable GitHub
Copilot skills. Each published skill is installed into a team member's local
Copilot skills directory, where the desktop app can discover it.

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

`@website-styling-audit` installs only `skills/website-styling-audit`. The
skill has no project-specific package dependencies, but live audits require a
working Playwright MCP browser capability and Python 3.8 or newer for the
standard-library report embedding and validation steps. The skill checks these
requirements before navigation or local output and never installs them
implicitly. Repackaging an existing audit bundle without navigation does not
require a browser.

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
