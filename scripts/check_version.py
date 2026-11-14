#!/usr/bin/env python3
"""Step 28: CI gate — every build must ship a NEW version.

Thuoc Vui bumps `version:` in pubspec.yaml by hand on every release
(both versionName and build number, e.g. 1.2.35+38 -> 1.2.36+39 -> 1.2.37+40;
see the Thuoc Vui git log). Ace Remote forgot to do that for 11 RDP
builds (runs #5-#15 all shipped 1.4.0+5), so CI now enforces it: the
build FAILS when the version in pubspec.yaml is unchanged from the
previous commit, or when the build number did not strictly increase
(Android refuses a lower/equal versionCode on update).

Usage:
  python3 scripts/check_version.py [current_pubspec] [previous_ref_or_file]

Defaults: current = pubspec.yaml, previous = HEAD~1 (read with
`git show HEAD~1:pubspec.yaml`; the checkout step needs fetch-depth >= 2).
If there is no previous commit (first commit in the repo) the check is
skipped with a warning.
"""

import re
import subprocess
import sys

VERSION_RE = re.compile(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+(\d+)\s*$",
                        re.MULTILINE)


def parse_version(text, where):
    m = VERSION_RE.search(text)
    if not m:
        print(f"check_version: no `version: X.Y.Z+N` found in {where}",
              file=sys.stderr)
        sys.exit(1)
    return m.group(1), int(m.group(2))


def read_previous(ref_or_file):
    """Return the previous pubspec.yaml text, or None when unavailable."""
    try:
        with open(ref_or_file, encoding="utf-8") as f:
            return f.read()
    except OSError:
        pass
    try:
        out = subprocess.run(
            ["git", "show", f"{ref_or_file}:pubspec.yaml"],
            capture_output=True, text=True, check=True)
        return out.stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


def main():
    current_path = sys.argv[1] if len(sys.argv) > 1 else "pubspec.yaml"
    previous_ref = sys.argv[2] if len(sys.argv) > 2 else "HEAD~1"
    try:
        with open(current_path, encoding="utf-8") as f:
            current_text = f.read()
    except OSError as e:
        print(f"check_version: cannot read {current_path}: {e}",
              file=sys.stderr)
        return 1
    cur_name, cur_code = parse_version(current_text, current_path)

    previous_text = read_previous(previous_ref)
    if previous_text is None:
        print(f"check_version: no previous version to compare "
              f"(ref {previous_ref} unavailable) — skipping check")
        print(f"check_version: current version is {cur_name}+{cur_code}")
        return 0
    prev_name, prev_code = parse_version(previous_text, previous_ref)

    print(f"check_version: previous {prev_name}+{prev_code} -> "
          f"current {cur_name}+{cur_code}")
    errors = []
    if (cur_name, cur_code) == (prev_name, prev_code):
        errors.append(
            "version is UNCHANGED from the previous commit — bump "
            "`version:` in pubspec.yaml (both versionName and build number, "
            "e.g. 1.4.0+5 -> 1.5.0+16) and add a CHANGELOG.md entry")
    if cur_code <= prev_code:
        errors.append(
            f"build number did not increase ({prev_code} -> {cur_code}) — "
            "Android refuses an update with a lower/equal versionCode")
    if errors:
        for e in errors:
            print(f"check_version: ERROR: {e}", file=sys.stderr)
        return 1
    print("check_version: OK — version increased")
    return 0


if __name__ == "__main__":
    sys.exit(main())
