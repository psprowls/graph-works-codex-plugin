#!/usr/bin/env bash
# Tests for resolve-workspace.sh — the pure-bash workspace resolver.
# Run: bash resolve-workspace.test.sh   (exit 0 = all pass)
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOLVER="$SCRIPT_DIR/resolve-workspace.sh"

pass=0
fail=0

# assert_eq <name> <expected> <actual>
assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass=$((pass + 1))
    echo "ok   - $name"
  else
    fail=$((fail + 1))
    echo "FAIL - $name"
    echo "        expected: [$expected]"
    echo "        actual:   [$actual]"
  fi
}

TMP="$(mktemp -d)"
TMP="$(cd "$TMP" && pwd -P)"   # resolve /var -> /private/var so paths compare equal
trap 'rm -rf "$TMP"' EXIT

# --- (a) GRAPH_WORKS_DIR set -> echoes it, exit 0 ---------------------
out="$(GRAPH_WORKS_DIR=/some/ws bash "$RESOLVER" 2>/dev/null)"
rc=$?
assert_eq "env var: echoes value" "/some/ws" "$out"
assert_eq "env var: exit 0" "0" "$rc"

# env var beats on-disk discovery
mkdir -p "$TMP/proj_a/.git" "$TMP/proj_a/.works"
out="$(cd "$TMP/proj_a" && GRAPH_WORKS_DIR=/env/ws bash "$RESOLVER" 2>/dev/null)"
assert_eq "env var beats discovery" "/env/ws" "$out"

# --- (b) walk-up finds .git; <repo>/.works exists -> echoes it -------------
mkdir -p "$TMP/proj_b/.git" "$TMP/proj_b/.works"
out="$(cd "$TMP/proj_b" && env -u GRAPH_WORKS_DIR bash "$RESOLVER" 2>/dev/null)"
rc=$?
assert_eq "discovery: echoes <repo>/.works" "$TMP/proj_b/.works" "$out"
assert_eq "discovery: exit 0" "0" "$rc"

# nested cwd exercises the walk-up
mkdir -p "$TMP/proj_b/a/b/c"
out="$(cd "$TMP/proj_b/a/b/c" && env -u GRAPH_WORKS_DIR bash "$RESOLVER" 2>/dev/null)"
assert_eq "discovery: walk-up from nested cwd" "$TMP/proj_b/.works" "$out"

# worktree-style .git FILE (not dir) also counts as a repo root
mkdir -p "$TMP/wt/.works"
printf 'gitdir: /elsewhere/.git/worktrees/wt\n' > "$TMP/wt/.git"
out="$(cd "$TMP/wt" && env -u GRAPH_WORKS_DIR bash "$RESOLVER" 2>/dev/null)"
assert_eq "discovery: .git file (worktree) counts" "$TMP/wt/.works" "$out"

# caller-supplied start dir argument
out="$(cd "$TMP" && env -u GRAPH_WORKS_DIR bash "$RESOLVER" "$TMP/proj_b/a/b/c" 2>/dev/null)"
assert_eq "start-dir arg: walks up from arg not PWD" "$TMP/proj_b/.works" "$out"

# --- (c) repo WITHOUT .works/ -> empty (never invents a path) --------------
mkdir -p "$TMP/proj_c/.git" "$TMP/proj_c/deep"
out="$(cd "$TMP/proj_c/deep" && env -u GRAPH_WORKS_DIR bash "$RESOLVER" 2>/dev/null)"
rc=$?
assert_eq "repo without .works/: empty stdout" "" "$out"
assert_eq "repo without .works/: exit 0" "0" "$rc"

# nested repo binds to the FIRST (inner) repo root — the outer repo's
# .works/ must NOT leak through
mkdir -p "$TMP/outer/.git" "$TMP/outer/.works" "$TMP/outer/inner/.git" "$TMP/outer/inner/src"
out="$(cd "$TMP/outer/inner/src" && env -u GRAPH_WORKS_DIR bash "$RESOLVER" 2>/dev/null)"
assert_eq "nested repo: binds to inner root, empty" "" "$out"

# a .works path that exists but is a FILE does not count
mkdir -p "$TMP/proj_f/.git"
touch "$TMP/proj_f/.works"
out="$(cd "$TMP/proj_f" && env -u GRAPH_WORKS_DIR bash "$RESOLVER" 2>/dev/null)"
assert_eq ".works is a file: empty" "" "$out"

# --- (d) graph-works discovery chain ------------------------------------

# explicit argument wins over GRAPH_WORKS_DIR
mkdir -p "$TMP/r2/.git"
mkdir -p "$TMP/explicit"; : > "$TMP/explicit/workspace.yaml"
mkdir -p "$TMP/envws"; : > "$TMP/envws/workspace.yaml"
out="$(GRAPH_WORKS_DIR="$TMP/envws" bash "$RESOLVER" "$TMP/explicit" 2>/dev/null)"
assert_eq "explicit argument wins over GRAPH_WORKS_DIR" "$TMP/explicit" "$out"

# no git repo anywhere prints nothing and exits 0
mkdir -p "$TMP/bare/dir"
out="$(cd "$TMP/bare/dir" && env -u GRAPH_WORKS_DIR bash "$RESOLVER" 2>/dev/null)"
rc=$?
assert_eq "no git repo anywhere: empty stdout" "" "$out"
assert_eq "no git repo anywhere: exit 0" "0" "$rc"

echo "-------------------------------------"
echo "pass=$pass fail=$fail"
[[ "$fail" -eq 0 ]]
