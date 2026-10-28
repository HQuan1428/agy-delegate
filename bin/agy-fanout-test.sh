#!/usr/bin/env bash
# Self-check for agy-fanout using stub `agy` / `ai-memory` binaries in a throwaway repo.
set -euo pipefail
FANOUT=$(realpath "$(dirname "$0")/agy-fanout")
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$T/stub" "$T/repo"
cat > "$T/stub/agy" <<'EOF'
#!/usr/bin/env bash
# stub: task prompts containing "BOOM" fail; others create a file named after the cwd.
# TDD keywords: GREEN-ON-2 (impl green from the 2nd session), NEVER-GREEN, EDIT-TEST, RAISE (SPEC-ISSUE)
printf '%s' "$2" > prompt.txt
if grep -q BOOM prompt.txt; then echo '{"conversation_id":"c-bad","status":"ERROR","response":"boom"}'; exit 0; fi
echo done > "out-$(basename "$PWD").txt"
c="$(git rev-parse --git-dir)/attempts"; n=$(( $(cat "$c" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$c"
if grep -q GREEN-ON-2 prompt.txt; then [ "$n" -ge 2 ] && echo green > impl.txt || echo red > impl.txt; fi
grep -q NEVER-GREEN prompt.txt && echo red > impl.txt
grep -q EDIT-TEST prompt.txt && { echo 'true  # AC-1' > test_e.sh; echo green > impl.txt; }
resp=ok; grep -q RAISE prompt.txt && resp='SPEC-ISSUE: impossible'
echo "{\"conversation_id\":\"c-$(basename "$PWD")\",\"status\":\"SUCCESS\",\"response\":\"$resp\\n\"}"
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
mkdir specs && printf '# X\nStatus: approved\n' > specs/x.md && printf '# D\nStatus: draft\n' > specs/d.md
echo hi > README && git add README specs && git commit -qm init
mkdir tasks && echo PLAN-XYZ > tasks/_plan.md
printf 'do a\nSpec: `specs/x.md`\nFiles: out-a.txt, `prompt.txt`\nVerify: `test -f out-a.txt`\n' > tasks/a.md
printf 'do b\nSpec: specs/x.md\nFiles: out-b.txt\nVerify: echo nope; false\n' > tasks/b.md
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
printf 'BOOM\nSpec: specs/x.md\n' > tasks/c.md
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
mkdir g; echo x > g/m.md
"$FANOUT" run g > "$T/g" 2>&1 && fail "task without Spec: accepted"; grep -q 'no Spec: line' "$T/g" || fail "task without Spec: accepted"
printf 'x\nSpec: specs/d.md\n' > g/m.md
"$FANOUT" run g > "$T/g" 2>&1 && fail "draft spec accepted"; grep -q 'not approved' "$T/g" || fail "draft spec accepted"
printf 'x\nSpec: specs/new.md\n' > g/m.md
"$FANOUT" run g > "$T/g" 2>&1 && fail "uncommitted spec accepted"; grep -q 'not committed' "$T/g" || fail "uncommitted spec accepted"
[ -e .worktrees/m ] && fail "worktree created for invalid task"

# 6. status + clean: only merged branches go
git merge -q --no-ff -m "merge a" task/a
[[ $("$FANOUT" status) =~ task/a\ +\+0\ +merged ]] || fail "status"
"$FANOUT" clean > "$T/o4"
git show-ref -q --verify refs/heads/task/a && fail "task/a not cleaned"
[ -d .worktrees/a ] && fail "worktree a not removed"
git show-ref -q --verify refs/heads/task/b || fail "unmerged task/b removed"
grep -q "kept    task/c (uncommitted" "$T/o4" || fail "dirty worktree c kept"

# 7. TDD: red tests on base; t green on 2nd session, n never green (+ SPEC-ISSUE, AC-2 untested), e edits its test
for t in t n e; do echo "grep -q green impl.txt  # AC-1" > "test_$t.sh"; done
git add test_*.sh && git commit -qm "red tests"
mkdir tdd
printf 'GREEN-ON-2 meets AC-1\nSpec: specs/x.md\nFiles: impl.txt, prompt.txt, out-t.txt\nTests: test_t.sh\nVerify: bash test_t.sh\n' > tdd/t.md
printf 'NEVER-GREEN RAISE meets AC-1 and AC-2\nSpec: specs/x.md\nFiles: impl.txt, prompt.txt, out-n.txt\nTests: test_n.sh\nVerify: bash test_n.sh\n' > tdd/n.md
printf 'EDIT-TEST meets AC-1\nSpec: specs/x.md\nFiles: impl.txt, prompt.txt, out-e.txt, test_e.sh\nTests: test_e.sh\nVerify: bash test_e.sh\n' > tdd/e.md
AGY_RETRIES=1 "$FANOUT" run tdd > "$T/o5" 2>&1 && fail "tdd run should exit 1"
grep -q '^OK    t' "$T/o5" && grep -q '^OK    e' "$T/o5" || { cat "$T/o5"; fail "tdd t/e ok"; }
grep -q '^FAIL  n  (verify red after 1 retries' "$T/o5" || fail "retry cap"
[ "$(cat .git/worktrees/t/attempts)" = 2 ] && [ "$(cat .git/worktrees/n/attempts)" = 2 ] || fail "attempt count"
grep -q 'never edit' .worktrees/t/prompt.txt && grep -q 'Verify failed' .worktrees/t/prompt.txt || fail "tdd prompt"
"$FANOUT" review tdd > "$T/o6" && fail "tdd review should exit 1"
grep -q 'tests: CHANGED  test_e.sh' "$T/o6" || { cat "$T/o6"; fail "test edit not flagged"; }
grep -q 'ac: missing  AC-2' "$T/o6" && [ "$(grep -c 'ac: missing' "$T/o6")" = 1 ] || fail "ac coverage"
grep -q 'spec-issue: SPEC-ISSUE: impossible' "$T/o6" || fail "spec issue"
grep -A3 '^== t' "$T/o6" | grep -q 'verify: pass' || fail "t green"
echo "all agy-fanout checks passed"
