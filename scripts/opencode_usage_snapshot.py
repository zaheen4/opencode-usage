#!/usr/bin/env python3
"""Write an OpenCode Usage sync snapshot without following symlinks.

The sync folder can be shared with other machines, so a peer may place a
symlink at the snapshot name. The snapshot is written to a new file in the
same directory and renamed over the destination, so the destination
directory entry is replaced instead of its symlink target.
"""

from __future__ import annotations

import json
import os
import sys
import tempfile

MAX_SNAPSHOT_BYTES = 4 * 1024 * 1024


def fail(message: str) -> int:
  print(f"opencode-usage: {message}", file=sys.stderr)
  return 1


def write_snapshot(destination: str, raw: bytes) -> None:
  directory = os.path.dirname(destination) or "."
  os.makedirs(directory, exist_ok=True)

  handle = -1
  temporary = ""
  try:
    handle, temporary = tempfile.mkstemp(
      dir=directory, prefix=".opencode-usage-", suffix=".tmp"
    )
    os.fchmod(handle, 0o600)
    with os.fdopen(handle, "wb") as stream:
      handle = -1
      stream.write(raw)
      stream.flush()
      os.fsync(stream.fileno())
    # rename(2) replaces the destination entry itself, so an existing symlink
    # is replaced rather than followed.
    os.replace(temporary, destination)
    temporary = ""
  finally:
    if handle >= 0:
      os.close(handle)
    if temporary:
      try:
        os.unlink(temporary)
      except OSError:
        pass


def main(argv: list[str]) -> int:
  if len(argv) != 2:
    return fail("usage: opencode_usage_snapshot.py DESTINATION")

  destination = argv[1]
  if destination == "":
    return fail("missing destination")

  raw = sys.stdin.buffer.read(MAX_SNAPSHOT_BYTES + 1)
  if len(raw) > MAX_SNAPSHOT_BYTES:
    return fail("snapshot is too large")
  try:
    json.loads(raw)
  except ValueError as exc:
    return fail(f"invalid snapshot: {exc}")

  try:
    write_snapshot(destination, raw)
  except OSError as exc:
    return fail(f"cannot write snapshot: {exc}")
  return 0


if __name__ == "__main__":
  sys.exit(main(sys.argv))
