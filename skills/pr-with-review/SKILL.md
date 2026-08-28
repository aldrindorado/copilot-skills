---
name: pr-with-review
description: Create a pull request using the Ezytire title convention. Use when the user asks to create a PR from the current branch.
---

# Pull Request Creation

Use this skill when the user asks to create a pull request from the current branch.

1. Create the pull request without running or requiring a code review.
2. Create the PR with this exact title format:

   ```text
   BRANCH-NAME - Brief description
   ```

   Example:

   ```text
   EOSB-748 - Add custom article URL slugs
   ```

3. Use the current branch name verbatim as the prefix. Capitalize the first word of the description; use concise sentence case.
4. Include a concise PR body with:
	- Summary of the Issue
   - Summary of the change
   - Validation performed
5. Do not run a code review as part of PR creation. However, if this same session has already completed a recent code review of the current branch's changes, add a `## Code Review` section to the PR body that accurately summarizes that review's outcome:
   - State the review scope and result, including any unresolved or accepted findings.
   - Do not claim a clean review when the prior review found issues.
   - Omit the section if no such review was completed in this session, if it reviewed a different branch, or if subsequent changes make its result stale.
