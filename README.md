# agy-delegate

Claude Code plugin: Claude plans, splits work into tasks and reviews; [Antigravity CLI](https://antigravity.google) (`agy`) executes them in parallel, each in its own git worktree. Optional shared memory between Claude and agy via [ai-memory](https://github.com/akitaonrails/ai-memory).

- `bin/agy-fanout run <tasks-dir> [jobs]`: runs every `*.md` in the dir through `agy -p --dangerously-skip-permissions`, one worktree/branch (`task/<name>`) per task, `jobs` at a time (default 4). `status` lists task branches, `clean` removes merged ones.
- `skills/delegate`: the plan → split → run → review → merge workflow (`/agy-delegate:delegate`).

Env: `AGY_JOBS` (default 4), `AGY_TIMEOUT` (per task, default `30m`), `AGY_RUN` (memory run id, default timestamp).

## Install

```bash
claude plugin marketplace add HQuan1428/agy-delegate
claude plugin install agy-delegate@agy-delegate
```

Requires `agy`, `git`, `python3`. Optionally put `bin/` on your `PATH` to call `agy-fanout` directly.

## Shared memory (optional)

```bash
curl -fsSL https://github.com/akitaonrails/ai-memory/releases/latest/download/install.sh | sh
ai-memory setup --agent claude-code --agent antigravity-cli
ai-memory doctor
```

When `ai-memory` is on `PATH`, `agy-fanout` does three things:
- Prepends a short instruction to each task telling agy to read `notes/delegate/<run>/plan.md`, which Claude writes.
- Tells agy to write `notes/delegate/<run>/<task>.md` when done. All calls are scoped to the repo's project: `.ai-memory.toml`, else the `upstream`/`origin` remote as `owner-repo`, else the dir name.
- After each task, runs `ai-memory finalize-session --agent antigravity-cli --session-id <id>`.

Without ai-memory everything still works, just without memory.

## Test

```bash
bash bin/agy-fanout-test.sh   # stubbed agy/ai-memory, no network
```

**Warning:** tasks run with `--dangerously-skip-permissions`; agy can execute any command without asking.
