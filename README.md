# agy-delegate

Claude Code plans and splits work into tasks; [Antigravity CLI](https://antigravity.google) (`agy`) executes them in parallel, each in its own git worktree.

- `agy-fanout <tasks-dir> [jobs]` — run every `*.md` in the dir through `agy -p --dangerously-skip-permissions`, one worktree/branch (`task/<name>`) per task, `jobs` at a time (default 4).
- `skills/delegate` — Claude Code skill describing the plan → split → run → review → merge workflow.

## Install

```bash
ln -s "$PWD/agy-fanout" ~/.local/bin/agy-fanout
ln -s "$PWD/skills/delegate" ~/.claude/skills/delegate
```

Warning: tasks run with `--dangerously-skip-permissions`; agy can execute any command without asking.
