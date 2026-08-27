---
name: copyright-owner-tireweb
description: >
  Enforces Tireweb copyright-owner normalization when editing source files that already include
  a copyright header (commonly in #region Copyright blocks). If Claude modifies code in such a file,
  it must update legacy owner names to "Tireweb" in that same file. Do not do repo-wide
  copyright-only rewrites unless explicitly asked.
---

# Tireweb Copyright Owner Normalization

## Purpose

Keep copyright-owner text consistent in modified files.

## Trigger

Apply this skill when:

1. Editing any source file that already contains a copyright header.
2. Creating a new source file that follows the existing `#region Copyright` convention.

## Core Rules

1. If you modify code in a file that has copyright-owner text, set owner/company to `Tireweb`.
2. Replace legacy owner names (including `Alister Jones and E-Solution Professionals` and `Tireweb Marketing`) with `Tireweb`.
3. Do not touch unrelated files just to normalize copyright.
4. If no code change is made to a file, do not edit its header.
5. Preserve existing header structure, spacing style, and region blocks as much as possible.

## Scope Guidance

- In-scope: file currently being edited for functional/code changes.
- Out-of-scope: bulk repository copyright cleanup unless the user explicitly requests it.

## Examples

### Allowed (same file being changed)

- You modify logic in a C# file and update:
  - `Copyright © Alister Jones and E-Solution Professionals. All rights reserved.`
  - to `Copyright © Tireweb. All rights reserved.`

### Not allowed (unrelated sweep)

- Running a repo-wide replacement only to update copyright owners when no such request was made.

## Notes

- This skill complements repo instructions and should be applied automatically during qualifying edits.
- When in doubt, prefer minimal edits and normalize owner text only in files you are already modifying.
