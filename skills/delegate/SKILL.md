---
name: delegate
description: Split a planned piece of work into independent tasks and run them in parallel with the agy (Antigravity) CLI, then review and merge the results. Use when the user says "delegate", "giao cho agy", "chạy song song", "/delegate", or when an approved plan has several independent, well-scoped implementation tasks. Claude designs, plans and reviews; agy executes.
---

# Delegate to agy

Claude owns design, planning, task splitting and review. `agy` (Antigravity CLI) owns execution.
Small or tightly coupled work: do it yourself, don't delegate.

## 1. Plan
Understand the codebase and agree the design with the user first. Repo must be a git repo with a clean working tree on the base branch.

## 2. Split into tasks
Write one file per task in `tasks/` at the repo root (`tasks/01-short-name.md`, ...). Each agy run sees ONLY its file, nothing from this conversation, so every task must be self-contained:

```markdown
# <Goal in one line>

## Context
What the project is, relevant files and how they fit. Design decisions already made.

## Do
Concrete steps.

## Scope
Files you may create/modify: <list>. Do not touch anything else.

## Done when
Verifiable criteria, including the exact command to run (tests/build/lint) and that it must pass.
```

Rules:
- Tasks must be independent: no two tasks touch the same file. If they must, sequence them (run in separate batches).
- Shared groundwork (types, interfaces, deps) goes in a first batch on its own, merged before the rest.
- Add `tasks/` to `.git/info/exclude` unless the user wants it committed.

## 3. Run
```bash
agy-fanout tasks/ [jobs]   # default 4 parallel, or $AGY_JOBS
```
Run it in the background (it can take a long time). Each task runs in `.worktrees/<name>` on branch `task/<name>`; output in `tasks/<name>.log`; leftover changes are auto-committed. It prints `OK`/`FAIL` per task.

## 4. Review and merge
For each task: `git diff <base>...task/<name>`, check it against the task's scope and "Done when", and run its verification command inside the worktree.
- Good: `git merge --no-ff task/<name>`.
- Bad or FAIL: read the log, sharpen the task file, then either re-run `agy-fanout` on a dir with just that task (the worktree is reused) or fix it yourself if small.
After merging run the full test suite on the base branch.

## 5. Clean up
```bash
git worktree remove .worktrees/<name> && git branch -d task/<name>
```
Report to the user: what each task did, what was merged, what failed and why.
