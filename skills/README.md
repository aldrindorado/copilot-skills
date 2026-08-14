# Published skills

Each immediate child directory is a published skill and must contain a
`SKILL.md` file. The installer copies these directories directly into a team
member's `$HOME\.copilot\skills` directory.

Keep every dependency used by a skill inside that skill's directory. Do not
place templates or shared documentation in this directory unless they are part
of a published skill.
