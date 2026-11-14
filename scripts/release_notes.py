#!/usr/bin/env python3
"""Step 28: build Firebase App Distribution release notes from CHANGELOG.md.

Thuoc Vui does NOT pass release notes to Firebase at all (its workflow
has no `releaseNotes` parameter — the detailed notes An sees for Thuoc
Vui are the per-release commit message, e.g. "Thuoc Vui v1.2.37: ...",
plus the delivery note in chat). Ace Remote does one better: every
release adds a curated entry to CHANGELOG.md, and CI takes the newest
entry as the release notes, so App Tester shows exactly what changed.

Output (first line is the version, then the entry body):
  Ace Remote 1.5.0 (16)

  - Phien ban tang len 1.5.0 (16): ...
  - ...

Fallback: when CHANGELOG.md is missing, has no `## [...]` section, or
its newest version does not match pubspec.yaml, warn on stderr and use
the current commit message (`git log -1`) instead, so the build never
fails just because the notes are missing. The version gate
(scripts/check_version.py) is the hard check; this script is lenient.

Usage:
  python3 scripts/release_notes.py [changelog] [output] [pubspec]
Defaults: CHANGELOG.md, release-notes.txt, pubspec.yaml.
"""

import re
import subprocess
import sys

HEADER_RE = re.compile(r"^## \[([^\]]+)\]\s*(?:-\s*(.*))?\s*$")
VERSION_RE = re.compile(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+(\d+)\s*$",
                        re.MULTILINE)


def pubspec_version(path):
    try:
        with open(path, encoding="utf-8") as f:
            m = VERSION_RE.search(f.read())
    except OSError:
        return None
    if not m:
        return None
    return m.group(1), int(m.group(2))


def changelog_section(path):
    """Return (version_string, body_lines) of the newest section, or None."""
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError:
        return None
    start = None
    version = None
    for i, line in enumerate(lines):
        m = HEADER_RE.match(line)
        if m:
            start, version = i, m.group(1).strip()
            break
    if start is None:
        return None
    body = []
    for line in lines[start + 1:]:
        if line.startswith("## "):
            break
        body.append(line)
    while body and not body[0].strip():
        body.pop(0)
    while body and not body[-1].strip():
        body.pop()
    return version, body


def commit_message():
    try:
        out = subprocess.run(
            ["git", "log", "-1", "--pretty=%s%n%n%b"],
            capture_output=True, text=True, check=True)
        return out.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


def main():
    changelog_path = sys.argv[1] if len(sys.argv) > 1 else "CHANGELOG.md"
    output_path = sys.argv[2] if len(sys.argv) > 2 else "release-notes.txt"
    pubspec_path = sys.argv[3] if len(sys.argv) > 3 else "pubspec.yaml"

    pub = pubspec_version(pubspec_path)
    section = changelog_section(changelog_path)

    notes = None
    if section is not None and pub is not None:
        change_version, body = section
        # CHANGELOG versions look like "1.5.0+16".
        if change_version == f"{pub[0]}+{pub[1]}" and body:
            notes = "\n".join(body)
        else:
            print(f"release_notes: WARNING: newest CHANGELOG entry "
                  f"({change_version}) does not match pubspec "
                  f"({pub[0]}+{pub[1]}) — falling back to commit message",
                  file=sys.stderr)
    elif section is not None and pub is None:
        print("release_notes: WARNING: cannot read pubspec version — "
              "falling back to commit message", file=sys.stderr)
    else:
        print("release_notes: WARNING: no usable CHANGELOG section — "
              "falling back to commit message", file=sys.stderr)

    if notes is None:
        notes = commit_message()
    if not notes:
        notes = ("Ace Remote RDP prototype — see the commit message for "
                 "what changed.")
        print("release_notes: WARNING: no commit message either — using "
              "generic fallback", file=sys.stderr)

    if pub is not None:
        header = f"Ace Remote {pub[0]} ({pub[1]})"
    else:
        header = "Ace Remote"
    text = f"{header}\n\n{notes}\n"
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"release_notes: wrote {output_path} "
          f"({len(text.splitlines())} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
