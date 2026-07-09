#!/usr/bin/env python3
"""Transform `aws ssm get-parameters-by-path` JSON into Env-file lines.

Usage: render-env.py <prefix>    (JSON on stdin, env lines on stdout)

Part of the M5 render (ADR 0022). Fails closed: any key or value the
env-file format cannot represent aborts with exit 1. Values pass through
raw; the consuming compose files declare `format: raw`, so no quoting or
interpolation applies. stderr reports counts and key names, never values.
Stdlib only; runs under the Host's system python3.
"""
import json
import re
import sys

KEY_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")


def fail(message: str) -> int:
    print(f"render-env: {message}", file=sys.stderr)
    return 1


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: render-env.py <prefix>", file=sys.stderr)
        return 2
    prefix = sys.argv[1]
    if not prefix.endswith("/"):
        prefix += "/"

    try:
        doc = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        return fail(f"invalid JSON on stdin: {exc}")

    pairs: dict[str, str] = {}
    for param in doc.get("Parameters", []):
        name = param["Name"]
        value = param["Value"]
        if not name.startswith(prefix):
            return fail(f"{name} is outside {prefix}")
        key = name[len(prefix):]
        if "/" in key:
            return fail(f"{name} nests deeper than {prefix}<KEY>")
        if not KEY_RE.fullmatch(key):
            return fail(f"key {key!r} is not UPPER_SNAKE_CASE")
        if key in pairs:
            return fail(f"duplicate key {key}")
        if "\n" in value or "\r" in value:
            return fail(f"value of {key} contains a line break")
        if value != value.strip():
            return fail(f"value of {key} has leading or trailing whitespace")
        pairs[key] = value

    for key in sorted(pairs):
        sys.stdout.write(f"{key}={pairs[key]}\n")
    if pairs:
        print(f"render-env: {len(pairs)} keys: {' '.join(sorted(pairs))}", file=sys.stderr)
    else:
        print(f"render-env: warning: no Parameters under {prefix}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
