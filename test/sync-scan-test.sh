#!/usr/bin/env bash
# Sync scan regression tests: the script embedded in Main.qml must be valid
# bash and must bound what it reads out of the shared sync folder.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="${PYTHON:-/usr/bin/python3}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

SCRIPT="$TMP/scan.sh"

# Rebuild the script exactly as QML does: same array, same join separator.
"$PYTHON" -S - "$ROOT/Main.qml" "$SCRIPT" <<'PY' || exit 1
import json, re, sys

source = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r"var script = \[(.*?)\]\.join\((.*?)\)", source, re.S)
if not match:
  sys.exit("FAIL: could not find the sync scan script in Main.qml")

constants = {"root.syncMaxFileBytes": "1048576", "root.syncMaxTotalBytes": "16777216",
             "root.syncMaxFiles": "64"}

body, separator = match.group(1), match.group(2).strip()
if not (separator.startswith('"') and separator.endswith('"')):
  sys.exit(f"FAIL: unexpected join separator {separator!r}")
separator = json.loads(separator)

items, current, in_string, escaped = [], "", False, False
for char in body:
  if in_string:
    current += char
    if escaped:
      escaped = False
    elif char == "\\":
      escaped = True
    elif char == '"':
      in_string = False
  elif char == '"':
    in_string = True
    current += char
  elif char == ",":
    items.append(current)
    current = ""
  else:
    current += char
if current.strip():
  items.append(current)

lines = []
for item in items:
  # Split on + only outside string literals; a quoted "+" is data, not an
  # operator (e.g. "  total=$(( total + size ))").
  parts, current, in_string, escaped = [], "", False, False
  for char in item.strip():
    if in_string:
      current += char
      if escaped:
        escaped = False
      elif char == "\\":
        escaped = True
      elif char == '"':
        in_string = False
    elif char == '"':
      in_string = True
      current += char
    elif char == "+":
      parts.append(current)
      current = ""
    else:
      current += char
  if current.strip():
    parts.append(current)

  text = ""
  for part in parts:
    part = part.strip()
    if not part:
      continue
    if part.startswith('"'):
      text += json.loads(part)
    elif part in constants:
      text += constants[part]
    else:
      sys.exit(f"FAIL: unsupported expression in scan script: {part!r}")
  lines.append(text)

open(sys.argv[2], "w", encoding="utf-8").write(separator.join(lines))
PY

bash -n "$SCRIPT" || fail "scan script is not valid bash"

# Run it the way Main.qml does: bash -c <script> <syncDir>, so $0 is the dir.
run_scan() {
  bash -c "$(<"$SCRIPT")" "$1"
}

# --------------------------------------------------------------- behaviour
SHARED="$TMP/shared"
mkdir -p "$SHARED"
printf '{"schemaVersion":1,"deviceId":"desktop"}\n' > "$SHARED/desktop.json"
"$PYTHON" -S -c 'import sys; sys.stdout.write("x" * (1024 * 1024 + 1))' > "$SHARED/oversized.json"
printf 'not json\n' > "$SHARED/broken.json"

OUT="$(run_scan "$SHARED")" || fail "scan script exited non-zero"

MARKERS="$(grep -c '^===' <<<"$OUT" || true)"
[[ "$MARKERS" -eq 4 ]] || fail "expected 2 emitted files (4 markers), got $MARKERS: $OUT"
grep -q '^===.*/desktop.json===$' <<<"$OUT" || fail "normal snapshot was not read"
grep -q '^===.*/broken.json===$' <<<"$OUT" \
  || fail "oversized/unparsable handling dropped the wrong file"
grep -q '^===.*/oversized.json===$' <<<"$OUT" && fail "oversized file was read"

# A path with spaces must survive without word splitting.
SPACED="$TMP/shared dir"
mkdir -p "$SPACED"
printf '{"schemaVersion":1}\n' > "$SPACED/a b.json"
SPACED_OUT="$(run_scan "$SPACED")" || fail "scan failed on a path with spaces"
grep -q '^===.*/a b.json===$' <<<"$SPACED_OUT" || fail "path with spaces was mishandled"

# The byte budget must hold even when every file is individually legal.
BUDGET="$TMP/budget"
mkdir -p "$BUDGET"
for i in $(seq 1 20); do
  "$PYTHON" -S -c 'import sys; sys.stdout.write("x" * 1048576)' > "$BUDGET/f$i.json"
done
BUDGET_OUT="$(run_scan "$BUDGET")" || fail "scan failed under the byte budget"
BUDGET_BYTES=$(LC_ALL=C; printf '%s' "$BUDGET_OUT" | wc -c)
[[ "$BUDGET_BYTES" -le $((16 * 1024 * 1024 + 4096)) ]] \
  || fail "scan read $BUDGET_BYTES bytes, over the 16 MiB budget"

# The file-count budget must hold with many small files.
MANY="$TMP/many"
mkdir -p "$MANY"
for i in $(seq 1 70); do printf '{"schemaVersion":1}\n' > "$MANY/f$i.json"; done
MANY_OUT="$(run_scan "$MANY")" || fail "scan failed under the file budget"
MANY_COUNT=$(( $(grep -c '^===' <<<"$MANY_OUT" || true) / 2 ))
[[ "$MANY_COUNT" -eq 64 ]] || fail "expected 64 files to be read, got $MANY_COUNT"

# A missing directory is not an error; it just yields nothing.
EMPTY_OUT="$(run_scan "$TMP/nonexistent")" || fail "missing directory was an error"
[[ -z "$EMPTY_OUT" ]] || fail "missing directory produced output"

echo "sync scan tests passed (64-file and 16 MiB budgets enforced)"
