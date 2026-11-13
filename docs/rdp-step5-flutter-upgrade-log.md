# Step 5 — stopped at the default compileSdk requirement

2026-11-13; branch `rdp-prototype`; starting HEAD `78a4cf1`.

## Official evidence

- [Flutter 3.50 announcement](https://flutter.dev/blog/whats-new-in-flutter-3-50),
  Android / Updated Android toolchain defaults: AGP 9.3.1, Gradle 9.5.0,
  KGP 2.4.20, Java minimum 17; default compileSdk **36**.
  The AGP 9 new DSL section describes support subject to plugin migration.
- [Flutter migration guide](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin):
  AGP 9 requires Kotlin migration; Flutter 3.44 introduced temporary legacy
  KGP support. Upgrading Flutter alone does not migrate every Android plugin.
- [Official Linux release manifest](https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json),
  fetched with curl (exit 0), saved outside git at
  `/home/hatch/workspace/flutter-releases-step5.json`: current stable 3.50.0,
  ref `ab2912035e160d9cad6306df307576da6128ebdb`, Dart 3.14.0,
  release date `2026-11-11T19:05:47.758707Z`.
  Archive `stable/linux/flutter_linux_3.50.0-stable.tar.xz`, SHA256
  `6ea2d806fd57269ae783e6788e2a81fc26eaad782f1e0d0ff38623bb765ff9f5`.
  These are manifest values, not an installed SDK version or verified download hash.
- [Tagged FlutterExtension.kt](https://github.com/flutter/flutter/blob/3.50.0/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt):
  fetched source, line 23: `val compileSdkVersion: Int = 36`.
- [Tagged gradle_utils.dart](https://github.com/flutter/flutter/blob/3.50.0/packages/flutter_tools/lib/src/android/gradle_utils.dart):
  fetched source lines 34 / 40 / 56 set template Gradle 9.5.0,
  template AGP 9.3.1 and compileSdk 36 respectively.
  Line numbers here are from Python urllib command output; web rendering can differ.
- [AGP 9.1.1 compatibility](https://developer.android.com/build/releases/agp-9-1-0-release-notes#compatibility):
  supports API 37, minimum/default Gradle 9.3.1 and JDK 17.
- [Gradle 9 migration](https://docs.gradle.org/current/userguide/upgrading_major_version_9.html#removed_project_exec):
  Project.exec was removed. Existing Flutter 3.24.5 evidence remains in step 4.

Commands: `curl -fsSL --max-time 30` for the manifest URL above, then Python
JSON lookup using `current_release.stable`; Python urllib fetched the tagged
source URLs and printed version assignments with line numbers. An initial
manifest URL containing an extra `/flutter/` returned HTTP 404; the corrected
URL above succeeded. No tarball download was attempted.

## Result and exact blocker

The latest stable verified here supports AGP 9 / Gradle 9, but its default
compileSdk is **36 < 37**. It does not meet task item 1's explicit requirement
that the default must be >=37. No release satisfying all requested conditions
was established. This is a requirement mismatch, not evidence that Flutter
3.50 cannot build with an explicitly configured compileSdk 37.

Stopped before installation rather than silently relaxing that condition.
New SDK path / `flutter --version`: N/A (not installed).
Analyze: not run; issue count N/A. Tests: 0 executed, pass/fail N/A.
The historical 29 passing tests on 3.24.5 are not new-SDK validation.
New SDK project.exec grep: not performed; no absence claim is made from a
partial remote source inspection. Template files in an installed SDK were not
inspected. Defaults above are verified remote tagged source and release notes.
The toolchain contradiction is **not yet demonstrated resolved for this app**.
Actual Gradle 9 build validation must happen on CI later; none ran on this VM.

No application code, Android settings, workflows, layout or keyboard changed.
Existing `/home/hatch/workspace/flutter` was untouched. No APK/Gradle build,
push, SDK commit, credential access or PC access occurred.
Pre-existing uncommitted status edits were preserved and excluded from staging.

## Next step and estimate

Resolve the default-SDK requirement: permit setting app compileSdk explicitly
to 37 with Flutter 3.50.0, or wait for a stable whose default is >=37.
Then install separately, inspect all Gradle plugin sources and run analyze and
all tests. Estimate for that validation: 0.5–1 working day, conditional on
network and migration results. After passing, return to direction A: CI AAR
workflow plus plugin integration; earlier 2–4 working day estimate remains a
planning estimate, with CI packaging and device validation still uncertain.
No workflow/plugin implementation was started in step 5.

Final CLI `tokens used`: unavailable inside this active turn. The completed
CLI log counter is only available after the response finishes; no live counter
is substituted. The caller must append that exact value from the final CLI log.
