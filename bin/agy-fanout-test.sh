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
EOF
chmod +x "$T/stub/"*

cd "$T/repo"
git init -q -b main && git config user.email t@t && git config user.name t
git remote add origin git@github.com:Acme/API.git
echo hi > README && git add README && git commit -qm init
mkdir tasks && echo "do a" > tasks/a.md && echo "do b" > tasks/b.md
echo tasks/ >> .git/info/exclude

# 1. without ai-memory: both OK, no memory header
# isolate from real agy/ai-memory in ~/.local/bin
PATH="$T/nomem:/usr/local/bin:/usr/bin:/bin"; mkdir -p "$T/nomem"; ln -s "$T/stub/agy" "$T/nomem/agy"
"$FANOUT" run tasks 2 > "$T/o1" 2>&1 || { cat "$T/o1"; fail "run 1 exit"; }
grep -q 'done: 2 OK / 0 FAIL' "$T/o1" || fail "summary 1"
grep -q 'without shared memory' "$T/o1" || fail "no-memory warning"
[ "$(git rev-list --count main..task/a)" = 1 ] || fail "task/a commit"
grep -q 'Shared memory' .worktrees/a/prompt.txt && fail "header without ai-memory"
grep -q ok tasks/a.log || fail "log has response"

# 2. with ai-memory + one failing task: exit 1, header scoped to acme-api, finalize per session id
ln -s "$T/stub/ai-memory" "$T/nomem/ai-memory"
echo "BOOM" > tasks/c.md
AGY_RUN=r1 "$FANOUT" run tasks > "$T/o2" 2>&1 && fail "run 2 should exit 1"
grep -q 'done: 2 OK / 1 FAIL' "$T/o2" || { cat "$T/o2"; fail "summary 2"; }
grep -q 'project="acme-api"' .worktrees/b/prompt.txt || fail "project scope"
grep -q 'notes/delegate/r1/b.md' .worktrees/b/prompt.txt || fail "notes path"
grep -q -- '--session-id c-b' "$T/memcalls" || fail "finalize b"
grep -q -- '--all' "$T/memcalls" && fail "never --all"
grep -q 'project = "acme-api"' .worktrees/b/.ai-memory.toml || fail "worktree marker"
git show --stat task/b | grep -q ai-memory.toml && fail "marker committed"
[ -f tasks/a.log.1 ] || fail "log rotation"

# 3. guards
echo dirty >> README; "$FANOUT" run tasks >/dev/null 2>&1 && fail "dirty tree accepted"; git checkout -q README
echo x > "tasks/bad..name.md"; "$FANOUT" run tasks >/dev/null 2>&1 && fail "bad name accepted"; rm "tasks/bad..name.md"

# 4. status + clean: only merged branches go
git merge -q --no-ff -m "merge a" task/a
[[ $("$FANOUT" status) =~ task/a\ +\+0\ +merged ]] || fail "status"
"$FANOUT" clean > "$T/o4"
git show-ref -q --verify refs/heads/task/a && fail "task/a not cleaned"
[ -d .worktrees/a ] && fail "worktree a not removed"
git show-ref -q --verify refs/heads/task/b || fail "unmerged task/b removed"
grep -q "kept    task/c (uncommitted" "$T/o4" || fail "dirty worktree c kept"
echo "all agy-fanout checks passed"
