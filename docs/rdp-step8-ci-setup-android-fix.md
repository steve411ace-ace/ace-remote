# Step 8 — setup-android package fix

2026-11-13, branch `rdp-prototype`, base `bef6903`.

## Failure and confirmed cause

The supplied CI run #1 report (run ID `43434467564`) records failure in
`android-actions/setup-android@v3`: `Failed to find package 'tools'`, with
sdkmanager exiting 1. Later build and upload steps were skipped; no artifacts
were produced. The run log itself was not independently retrieved here.

The workflow had no `with:` block for this action. Upstream
[v3 action.yml](https://github.com/android-actions/setup-android/blob/v3/action.yml)
was inspected and confirms `packages` defaults to `tools platform-tools`.
That implicit `tools` request explains the supplied sdkmanager failure.

## Change

Set `packages: platform-tools` on the existing action. This overrides its
default and removes the obsolete `tools` request while retaining the action's
command-line tools, PATH and license setup. The subsequent SDK installation
step remains unchanged, including direct NDK download and SHA256/revision checks.
All other workflow steps, triggers, artifact behavior and version pins are
unchanged: JDK 17, Flutter 3.50.0, SDK 37, Build Tools 37.0.0, CMake 4.1.2,
NDK 29.0.14206865, FreeRDP 3.33.0 at
`5a10d7b6b79a2fbc62e8eba77085cd356dc303a6`.

## VM verification

- PyYAML `safe_load`: PASS.
- `bash -n`: PASS for all six workflow `run` blocks.
- `git diff --check`: PASS.
- `/home/hatch/workspace/flutter-3.50.0/bin/flutter analyze`: exit 1 before
  analysis starts; SDK cache writes fail with `Read-only file system`.
- `/home/hatch/workspace/flutter-3.50.0/bin/flutter test`: exit 1 before tests
  start, for the same SDK cache write failure (`engine.stamp.tmp.*` and
  `engine.realm`). No analyze/test pass is claimed.

Only workflow and this document were changed. No Gradle/APK build ran on VM,
no SDK was copied, and no push was performed.
Semantic comparison against HEAD also confirms the only workflow change is the
action's `packages` input. `git add` and `git commit` were attempted but both
failed because `.git/index.lock` cannot be created on the read-only filesystem.
No commit was created; HEAD remains `bef6903`.

## Remaining CI verification

A rerun must confirm setup succeeds, pinned SDK package/download availability,
NDK integrity, FreeRDP native dependency resolution and arm64 QA AAR generation,
JNI archive inspection and AAR upload, then the Flutter APK build with
`ACE_RDP=true` and artifact upload. Upstream uses Gradle 9.6.1 / AGP 9.2.1;
the app uses Gradle 9.5.0 / AGP 9.3.1. Their actual compilation, dependency
resolution and manifest/resource merging remain unverified by these syntax
checks. Device native loading and rendering still need runtime validation.

The completed current CLI log's final `tokens used` counter is unavailable
inside this active turn. No live token_count snapshot is substituted.
