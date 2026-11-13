# Step 4 A — confirmed consuming-toolchain blocker

2026-11-13; branch `rdp-prototype`; starting HEAD `b65ce5e`.
Stopped under task item 5 (technical contradiction). No workflow, plugin,
AAR dependency or layout implementation is claimed. The pre-existing uncommitted
edit to `docs/rdp-prototype-status.md` is preserved and excluded from this commit.

## New evidence

Maven access now works. Download succeeded (curl exit 0):

```sh
curl -fL --connect-timeout 10 --max-time 30 \
  https://dl.google.com/dl/android/maven2/androidx/core/core/1.19.0/core-1.19.0.aar \
  -o /tmp/ace-core.aar
unzip -p /tmp/ace-core.aar META-INF/com/android/build/gradle/aar-metadata.properties
```

Downloaded AAR SHA256:
`55445ad0ff025963929892569a0bfc6b4c68e60d8b7c965dcffba09048c36c8e`.
Metadata:

```properties
aarFormatVersion=1.0
aarMetadataVersion=1.0
minCompileSdk=37
minCompileMinorSdk=0
minCompileSdkExtension=0
minAndroidGradlePluginVersion=9.1.0
coreLibraryDesugaringEnabled=false
```

This dependency is explicitly declared by pinned FreeRDP's
`client/Android/Studio/freeRDPCore/build.gradle:70`. A local file AAR does not
carry its Maven dependency graph, so copying FreeRDP's AAR alone is insufficient.
Consuming the declared dependency requires changing the app's AGP 8.1.0
(`android/settings.gradle:21`), Gradle 8.3 (wrapper properties), and compileSdk 34
(Flutter 3.24.5 `packages/flutter_tools/gradle/src/main/groovy/flutter.groovy:45`).

The [AGP 9.1 compatibility table](https://developer.android.com/build/releases/agp-9-1-0-release-notes#compatibility)
currently documents 9.1.1 with Gradle minimum 9.3.1, JDK 17 and API 37 support.
However local Flutter **3.24.5**, framework `dec2ee5c1f`, Dart **3.5.4**, invokes
`project.exec` in `flutter.groovy:1687` when building Flutter artifacts.
[Gradle 9 removed Project.exec](https://docs.gradle.org/current/userguide/upgrading_major_version_9.html#removed_project_exec).
Simply upgrading the app to AGP 9 / Gradle 9 therefore conflicts with this
Flutter integration. This is source/metadata evidence, not an executed APK failure.
It does not establish that FreeRDP itself cannot build its AAR on CI.

An implementation needs a validated dependency downgrade in upstream FreeRDP,
or a changed Flutter integration/version constraint. Neither is silently chosen
here. A speculative SDK patch or metadata suppression is not a compatibility fix.

## VM checks for this attempt

Used the existing `/home/hatch/workspace/flutter/bin/flutter` in place:

- `flutter analyze --no-pub`: exit 0, **No issues found**, 5.9 seconds.
- `flutter test --no-pub`: exit 0, **29 passed**, 19 seconds.
  Existing hit-test warnings remain. These checks cover the unchanged app,
  not an RDP PlatformView implementation.

No Gradle command, APK build, PC access, push, release or Firebase upload ran.
No binary was added to git. Existing release workflow, agent, keyboard and
minSdk 23 remain unchanged. No new CI workflow exists, so pushing this evidence
commit alone will not validate AAR or APK builds.

## Remaining scope

After resolving the consuming-toolchain constraint, implement the requested
separate CI workflow and PlatformView. Upstream tool versions remain sourced
from Studio `build.gradle:10,15,44-54` (AGP 9.2.1, androidgitversion 0.4.14,
SDK 37, Build Tools 37.0.0, CMake 4.1.2, minSdk 29) and wrapper properties:3
(Gradle 9.6.1). NDK r29 revision 29.0.14206865 and its download checksum are
the previously verified values in `rdp-prototype-status.md`; Flutter 3.24.5 and
JDK 17 are also declared by the existing release workflow.
CI must still verify tool availability, tagged shallow-clone versioning,
AAR/native dependency packaging, manifest merging and APK compilation.
App minSdk must become 29 when the AAR integration is added.

Then implement real RDP rendering/lifecycle, physical viewport negotiation
(top logical size times devicePixelRatio), JNI input, NLA and Fold validation.
The existing 2–4 working day estimate applies after packaging/toolchain unblock;
unblock duration is unknown.

CLI usage snapshot read from
`/home/hatch/.codex/sessions/2026/11/13/rollout-2026-11-13T12-30-38-01a1d4e3-7199-7683-b8ea-b8116dcc769a.jsonl`:
token_count at `2026-11-13T12:31:35.249Z`, total **231,035**
(input 229,776, including cached input 189,440; output 1,259).
This is a live snapshot, not the final completed-turn total.
