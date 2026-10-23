# agy-delegate

Plugin for Claude Code and Codex: the lead agent plans, splits work into tasks and reviews; [Antigravity CLI](https://antigravity.google) (`agy`) executes them in parallel, each in its own git worktree. Optional shared memory between the lead agent and agy via [ai-memory](https://github.com/akitaonrails/ai-memory).

- `bin/agy-fanout run <tasks-dir> [jobs]`: runs every `*.md` in the dir through `agy -p --dangerously-skip-permissions`, one worktree/branch (`task/<name>`) per task, `jobs` at a time (default 4). `<tasks-dir>/_plan.md` is not a task: it is prepended to every task prompt (shared context, written once).
- `agy-fanout review <tasks-dir>`: one compact report for the whole batch: OK/FAIL, diffstat, changed files outside the task's `Files:` line, result of its `Verify:` command run in the worktree, log tail on FAIL. Exits 1 on any problem.
- `agy-fanout status` lists task branches, `clean` removes merged ones.
- `skills/delegate`: the plan → split → run → review → merge workflow (`/agy-delegate:delegate` in Claude Code, `$agy-delegate:delegate` in Codex).

Env: `AGY_JOBS` (default 4), `AGY_TIMEOUT` (per task, default `30m`), `AGY_MEMORY=1` (save worker reports to ai-memory), `AGY_RUN` (memory run id, default timestamp).

Why this shape: the lead agent's cost is roughly tool calls × conversation size, so `_plan.md` saves writing shared context N times and `review` turns several calls per task into one.

## Install

Claude Code:
```bash
claude plugin marketplace add HQuan1428/agy-delegate
claude plugin install agy-delegate@agy-delegate
```

Codex (reads the same `.claude-plugin/` manifests; start a new session after installing):
```bash
codex plugin marketplace add HQuan1428/agy-delegate
codex plugin add agy-delegate@agy-delegate
```
In Codex, `agy-fanout run` needs network, so approve it running outside the sandbox.

Requires `agy`, `git`, `python3`. Optionally put `bin/` on your `PATH` to call `agy-fanout` directly.

## Shared memory (optional)

```bash
curl -fsSL https://github.com/akitaonrails/ai-memory/releases/latest/download/install.sh | sh
ai-memory setup --agent claude-code --agent codex --agent antigravity-cli   # keep the lead agents you use
ai-memory doctor
```

Workers never call memory tools: on a one-file task, agy took 124–147k tokens / 90–154s when it read and wrote memory via MCP, versus 26k tokens / 14s with memory handled outside it. The lead agent reads memory once and folds what matters into `_plan.md`; `agy-fanout` writes memory via the `ai-memory` CLI.

When `ai-memory` is on `PATH`, each worktree gets an `.ai-memory.toml` pinning it to the repo's project (`.ai-memory.toml`, else the `upstream`/`origin` remote as `owner-repo`, else the dir name), and after each task `agy-fanout` runs `ai-memory finalize-session --agent antigravity-cli --session-id <id>`. With `AGY_MEMORY=1` it also saves each worker's final report as `notes/delegate/<run>/<task>.md`.

Without ai-memory everything still works, just without memory.

## Test

```bash
bash bin/agy-fanout-test.sh   # stubbed agy/ai-memory, no network
```

**Warning:** tasks run with `--dangerously-skip-permissions`; agy can execute any command without asking.
