#!/usr/bin/env bash
# Self-check for agy-fanout using stub `agy` / `ai-memory` binaries in a throwaway repo.
set -euo pipefail
FANOUT=$(realpath "$(dirname "$0")/agy-fanout")
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$T/stub" "$T/repo"
cat > "$T/stub/agy" <<'EOF'
#!/usr/bin/env bash
# stub: task prompts containing "BOOM" fail; others create a file named after the cwd
printf '%s' "$2" > prompt.txt
if grep -q BOOM prompt.txt; then echo '{"conversation_id":"c-bad","status":"ERROR","response":"boom"}'; exit 0; fi
echo done > "out-$(basename "$PWD").txt"
echo "{\"conversation_id\":\"c-$(basename "$PWD")\",\"status\":\"SUCCESS\",\"response\":\"ok\\n\"}"
EOF
cat > "$T/stub/ai-memory" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$T/memcalls"
[[ "\$*" == *"--body -"* ]] && cat >> "$T/membody"
exit 0
EOF
chmod +x "$T/stub/"*

cd "$T/repo"
git init -q -b main && git config user.email t@t && git config user.name t
git remote add origin git@github.com:Acme/API.git
echo hi > README && git add README && git commit -qm init
mkdir tasks && echo PLAN-XYZ > tasks/_plan.md
printf 'do a\nFiles: out-a.txt, `prompt.txt`\nVerify: `test -f out-a.txt`\n' > tasks/a.md
printf 'do b\nFiles: out-b.txt\nVerify: echo nope; false\n' > tasks/b.md
echo tasks/ >> .git/info/exclude

# 1. without ai-memory: both OK, _plan.md prepended and not run as a task, no memory
# isolate from real agy/ai-memory in ~/.local/bin
PATH="$T/nomem:/usr/local/bin:/usr/bin:/bin"; mkdir -p "$T/nomem"; ln -s "$T/stub/agy" "$T/nomem/agy"
"$FANOUT" run tasks 2 > "$T/o1" 2>&1 || { cat "$T/o1"; fail "run 1 exit"; }
grep -q 'done: 2 OK / 0 FAIL' "$T/o1" || fail "summary 1"
[ "$(git rev-list --count main..task/a)" = 1 ] || fail "task/a commit"
grep -q PLAN-XYZ .worktrees/a/prompt.txt && grep -q 'do a' .worktrees/a/prompt.txt || fail "plan prepended"
[ -e .worktrees/_plan ] && fail "_plan.md run as a task"
[ -e .worktrees/a/.ai-memory.toml ] && fail "marker without ai-memory"
grep -q ok tasks/a.log || fail "log has response"

# 2. ai-memory installed, AGY_MEMORY unset + one failing task: exit 1, finalize per session id, no notes
AGY_MEMORY=1 "$FANOUT" run tasks >/dev/null 2>&1 && fail "AGY_MEMORY=1 accepted without ai-memory"
ln -s "$T/stub/ai-memory" "$T/nomem/ai-memory"
echo "BOOM" > tasks/c.md
"$FANOUT" run tasks > "$T/o2" 2>&1 && fail "run 2 should exit 1"
grep -q 'done: 2 OK / 1 FAIL' "$T/o2" || { cat "$T/o2"; fail "summary 2"; }
grep -q -- '--session-id c-b --workspace default --project acme-api' "$T/memcalls" || fail "finalize b"
grep -q write-page "$T/memcalls" && fail "notes written without AGY_MEMORY=1"
grep -q memory_ .worktrees/b/prompt.txt && fail "memory instructions in prompt"
grep -q -- '--all' "$T/memcalls" && fail "never --all"
grep -q 'project = "acme-api"' .worktrees/b/.ai-memory.toml || fail "worktree marker"
git show --stat task/b | grep -q ai-memory.toml && fail "marker committed"
[ -f tasks/a.log.1 ] || fail "log rotation"

# 3. AGY_MEMORY=1: worker report saved as notes via CLI
AGY_RUN=r1 AGY_MEMORY=1 "$FANOUT" run tasks >/dev/null 2>&1 && fail "run 3 should exit 1"
grep -q -- '--project acme-api --path notes/delegate/r1/b.md' "$T/memcalls" || fail "notes path"
grep -q ok "$T/membody" || fail "notes body"

# 4. review: a clean; b out of scope + verify fails; c FAIL with log tail; exit 1
"$FANOUT" review tasks > "$T/o3" && fail "review should exit 1"
grep -q '^== a  OK  +[0-9]* commits' "$T/o3" || { cat "$T/o3"; fail "review a"; }
grep -q 'verify: pass  (test -f out-a.txt)' "$T/o3" || fail "verify a"
[ "$(grep -c 'scope: ok' "$T/o3")" = 1 ] || fail "scope a"
grep -q 'scope: OUT  prompt.txt' "$T/o3" || fail "scope b"
grep -q 'verify: FAIL  (echo nope; false)' "$T/o3" && grep -q '   | nope' "$T/o3" || fail "verify b"
grep -q '^== c  FAIL' "$T/o3" && grep -q '   | boom' "$T/o3" || fail "review c"
grep -q _plan "$T/o3" && fail "review lists _plan.md"

# 5. guards
echo dirty >> README; "$FANOUT" run tasks >/dev/null 2>&1 && fail "dirty tree accepted"; git checkout -q README
echo x > "tasks/bad..name.md"; "$FANOUT" run tasks >/dev/null 2>&1 && fail "bad name accepted"; rm "tasks/bad..name.md"

# 6. status + clean: only merged branches go
git merge -q --no-ff -m "merge a" task/a
[[ $("$FANOUT" status) =~ task/a\ +\+0\ +merged ]] || fail "status"
"$FANOUT" clean > "$T/o4"
git show-ref -q --verify refs/heads/task/a && fail "task/a not cleaned"
[ -d .worktrees/a ] && fail "worktree a not removed"
git show-ref -q --verify refs/heads/task/b || fail "unmerged task/b removed"
grep -q "kept    task/c (uncommitted" "$T/o4" || fail "dirty worktree c kept"
echo "all agy-fanout checks passed"
