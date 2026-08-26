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

Shared GitHub Copilot skills for the team
