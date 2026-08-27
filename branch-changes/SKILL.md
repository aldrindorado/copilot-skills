---
name: branch-changes
description: Lists changed files from a GitHub compare URL or base...head refs using gh api. Use when asked for "files changed" from compare UI.
---

Use this skill to return the file list from GitHub compare results in a consistent, reusable way.

## Accepted inputs

Support either input style:

1. Full compare URL (example: `https://github.com/tireweb-ezytire/Ezytire/compare/development...EOSB-770`)
2. Explicit parts: `owner/repo`, `base`, `head`

## Command to run

For this repository example:

```powershell
gh api repos/tireweb-ezytire/Ezytire/compare/development...EOSB-770 --jq ".files[].filename"
```

Generic form:

```powershell
gh api repos/<owner>/<repo>/compare/<base>...<head> --jq ".files[].filename"
```

Optional status + filename output:

```powershell
gh api repos/<owner>/<repo>/compare/<base>...<head> --jq '.files[] | "\(.status)\t\(.filename)"'
```

## Output requirements

- Return each changed file path exactly as GitHub reports it.
- Preserve API order unless the user asks to sort.
- If no files are returned, state that explicitly.
- If `gh` auth fails, report the auth error and stop.

## Notes

- Compare API file payloads can be truncated on very large diffs; if the user expects more files than returned, report that limitation and offer a local `git diff --name-only <base>...<head>` fallback.
