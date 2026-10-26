#!/usr/bin/env bash
# Snapshot writer regression tests: atomic replace, symlink destinations, and
# rejection of oversized or malformed input.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="${PYTHON:-/usr/bin/python3}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

writer() {
  "$PYTHON" -S "$ROOT/scripts/opencode_usage_snapshot.py" "$@"
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# No leftovers, whatever happened above.
assert_no_temp_files() {
  local dir=$1
  local stale
  stale="$(find "$dir" -maxdepth 1 -name '.opencode-usage-*.tmp' -print)"
  [[ -z "$stale" ]] || fail "temporary files left behind in $dir: $stale"
}

# ------------------------------------------------------------ normal write
SNAPSHOT_DIR="$TMP/shared"
mkdir -p "$SNAPSHOT_DIR"
printf '{"schemaVersion":1,"old":true}\n' > "$SNAPSHOT_DIR/desktop.json"
printf '{"schemaVersion":1,"deviceId":"desktop"}\n' | writer "$SNAPSHOT_DIR/desktop.json" \
  || fail "normal write failed"
jq -e '.deviceId == "desktop" and (.old == null)' \
  >/dev/null <"$SNAPSHOT_DIR/desktop.json" || fail "normal write produced unexpected content"
[[ "$(stat -c %a "$SNAPSHOT_DIR/desktop.json")" == "600" ]] \
  || fail "snapshot is not mode 600"
assert_no_temp_files "$SNAPSHOT_DIR"

# A missing destination directory is created.
printf '{"schemaVersion":1}\n' | writer "$TMP/new/dir/peer.json" \
  || fail "write into a missing directory failed"
[[ -f "$TMP/new/dir/peer.json" ]] || fail "missing directory was not created"

# ------------------------------------------------- symlink to an outside file
# A sync peer can place a symlink at the snapshot name. Replacing the
# destination must replace the link, not write through it.
SENTINEL="$TMP/outside/target.json"
mkdir -p "$TMP/outside"
printf 'SENTINEL-DO-NOT-OVERWRITE\n' > "$SENTINEL"
ln -s "$SENTINEL" "$SNAPSHOT_DIR/linked.json"
printf '{"schemaVersion":1,"deviceId":"linked"}\n' | writer "$SNAPSHOT_DIR/linked.json" \
  || fail "write over a symlink destination failed"
[[ "$(cat "$SENTINEL")" == "SENTINEL-DO-NOT-OVERWRITE" ]] \
  || fail "symlink target was overwritten: $(cat "$SENTINEL")"
[[ ! -L "$SNAPSHOT_DIR/linked.json" ]] || fail "symlink was preserved instead of replaced"
jq -e '.deviceId == "linked"' >/dev/null <"$SNAPSHOT_DIR/linked.json" \
  || fail "symlink replacement produced unexpected content"
assert_no_temp_files "$SNAPSHOT_DIR"

# Same, for a dangling symlink: the link must be replaced, not its target.
ln -s "$TMP/outside/never-created.json" "$SNAPSHOT_DIR/dangling.json"
printf '{"schemaVersion":1}\n' | writer "$SNAPSHOT_DIR/dangling.json" \
  || fail "write over a dangling symlink failed"
[[ ! -e "$TMP/outside/never-created.json" ]] \
  || fail "dangling symlink target was created"
[[ -f "$SNAPSHOT_DIR/dangling.json" && ! -L "$SNAPSHOT_DIR/dangling.json" ]] \
  || fail "dangling symlink was not replaced"

# ------------------------------------------------ rejection without clobbering
BEFORE="$(cat "$SNAPSHOT_DIR/desktop.json")"

"$PYTHON" -S -c 'import sys; sys.stdout.write("x" * (4 * 1024 * 1024 + 1))' \
  | writer "$SNAPSHOT_DIR/desktop.json" 2>/dev/null \
  && fail "oversized snapshot was accepted"
[[ "$(cat "$SNAPSHOT_DIR/desktop.json")" == "$BEFORE" ]] \
  || fail "oversized snapshot modified the destination"

printf '{not json\n' | writer "$SNAPSHOT_DIR/desktop.json" 2>/dev/null \
  && fail "malformed snapshot was accepted"
[[ "$(cat "$SNAPSHOT_DIR/desktop.json")" == "$BEFORE" ]] \
  || fail "malformed snapshot modified the destination"

printf '{"schemaVersion":1}\n' | writer "" 2>/dev/null \
  && fail "empty destination was accepted"

assert_no_temp_files "$SNAPSHOT_DIR"

echo "snapshot writer tests passed"
