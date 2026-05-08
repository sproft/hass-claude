#!/usr/bin/env python3
"""Pull the embedded `CMD ["/bin/bash", "-c", "<script>"]` boot script out of
claudecode/Dockerfile so CI can lint it with bash -n / shellcheck.

Approach:
  1. Read the Dockerfile.
  2. Collapse Dockerfile line-continuations (a backslash followed by a newline
     plus indent inside a single instruction).
  3. Find the CMD instruction, JSON-parse the argv array.
  4. Print the third element (the bash script) on stdout.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

DEFAULT_PATH = Path("claudecode/Dockerfile")


def main(argv: list[str]) -> int:
    path = Path(argv[1]) if len(argv) > 1 else DEFAULT_PATH
    src = path.read_text()

    # Collapse Dockerfile line continuations: a backslash at end of a logical
    # source line, then newline plus optional whitespace on the next line.
    joined = re.sub(r"\\\n[ \t]*", "", src)

    match = re.search(r"^CMD\s+(\[.*\])\s*$", joined, re.MULTILINE)
    if not match:
        print("error: no CMD instruction found in Dockerfile", file=sys.stderr)
        return 1

    try:
        argv_array = json.loads(match.group(1))
    except json.JSONDecodeError as exc:
        print(f"error: CMD argv is not valid JSON: {exc}", file=sys.stderr)
        return 1

    if (
        not isinstance(argv_array, list)
        or len(argv_array) < 3
        or argv_array[0] != "/bin/bash"
        or argv_array[1] != "-c"
    ):
        print(
            f"error: CMD shape unexpected, want exec form "
            f'["/bin/bash", "-c", "<script>"], got: {argv_array[:2]}',
            file=sys.stderr,
        )
        return 1

    sys.stdout.write("#!/bin/bash\n")
    sys.stdout.write("# Auto-extracted from Dockerfile by extract-boot-script.py.\n")
    sys.stdout.write("# Edits should be made in the Dockerfile, not here.\n")
    sys.stdout.write(argv_array[2])
    if not argv_array[2].endswith("\n"):
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
