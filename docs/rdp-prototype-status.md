# Step 7b — CI workflow + app-local RDP waiting PlatformView

2026-11-13; branch `rdp-prototype`; base `c971db2`.
Toolchain commit reviewed and retained: AGP 9.3.1 / Gradle 9.5.0 /
KGP 2.4.20, compileSdk 37, minSdk 29, Build Tools 37.0.0,
NDK 29.0.14206865 and both temporary AGP compatibility flags.

Implemented separate branch/manual AAR+APK artifact workflow, explicit raw-AAR
runtime dependencies, app-local Android FlutterPlugin/PlatformView + status
channel, and ACE_RDP waiting screen with exact 50/50 body layout using unchanged
v1.4 laptop keyboard. No RDP connection or JNI input yet; keyboard is inert in
waiting mode. Full implementation, source evidence, CI contract and limitations:
[Step 7b details](rdp-step7b-ci-plugin.md).

Actual VM commands used `/home/hatch/workspace/flutter-3.50.0/bin/flutter`:
- Before edits: `analyze` exit 0, no issues (16.1s); `test --reporter expanded`
  exit 0, 29/29 passed.
- After edits: `analyze` exit 0, no issues (16.4s); `test --reporter expanded`
  exit 0, 30/30 passed (one new RDP layout/no-HTTP test).
- Existing nonfatal hit-test warnings remain. Post-change logs are outside git:
  `/home/hatch/workspace/rdp-step7b-analyze.log` and `rdp-step7b-test.log`.
- Workflow YAML parsed with PyYAML; all run blocks passed `bash -n`.
  `git diff --check` passed. No Gradle/APK build ran on VM.

AAR/APK builds, Maven/native packaging, manifest merge/minSdk compatibility
remain CI checks after Muse pushes. Native loading, waiting surface and lifecycle
remain Fold runtime checks. No no-crash device result is claimed. No push,
release, PC access, credentials or binary commit. Next: real connection,
viewport-sized rendering, lifecycle, JNI input and NLA; estimate 2–4 working days
after CI succeeds, subject to device findings.

Final current CLI `tokens used` is unavailable during this turn; supplied
interrupted log contains no final usage line. Obtain it from the completed
current CLI log, without substituting a live snapshot.

---

# Step 6b — compileSdk 37 and Flutter 3.50 validation passed

2026-11-13; branch `rdp-prototype`; starting HEAD `79ccebc`.
This entry supersedes the step 5 default-compileSdk blocker below. The user
explicitly authorized app compileSdk 37. Existing step 4 audit edits are
preserved and included in this commit.

## Changes

- `android/app/build.gradle:10`: `flutter.compileSdkVersion` -> `37`
  (resolved old default 34 on Flutter 3.24.5; new SDK default is 36).
- `lib/agent.dart`, `lib/main.dart`, `test/agent_test.dart`,
  `test/remote_test.dart`, `test/security_test.dart`: replace deprecated
  `flutter/material.dart` imports with `material_ui/material_ui.dart`.
  `lib/main.dart` also obtains GlobalMaterialLocalizations from material_ui
  and replaces two deprecated DropdownButtonFormField `value` arguments
  with `initialValue`.
- `pubspec.yaml`: pin `material_ui: 1.0.0` to the initial frozen-framework
  equivalent rather than adopting later UI feature releases. `pubspec.lock`
  records this package, its cupertino_ui dependency, and Flutter/Dart SDK
  dependency resolution changes. No general pub upgrade was run.
- `analysis_options.yaml`: Flutter analyze automatically added exclusions
  for `build/**` and `android/**`; retained the SDK migration.

Migration followed the official manual import/localization instructions:
https://docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui
No diagnostics required minSdk/targetSdk or Kotlin migration in these Dart
checks. minSdk stays 23; targetSdk still follows Flutter (now default 36).
The SDK checker has errorMinSdkVersion 23 and warnMinSdkVersion 24.
No Android compilation or Kotlin compatibility is established by Dart checks.

## Commands and results

All Flutter commands used `/home/hatch/workspace/flutter-3.50.0/bin/flutter`.
`flutter --version`: Flutter 3.50.0 stable, framework ab2912035e,
Dart 3.14.0. Used the preinstalled SDK; no reinstall or archive download.

1. `flutter analyze`: exit 1, 8 deprecated_member_use infos (five Material
   imports, GlobalMaterialLocalizations, two dropdown value arguments).
2. After the minimal migration, `flutter analyze`: exit 0,
   **No issues found**, 18.7 seconds.
3. `flutter test --reporter expanded`, full suite run 1: exit 0,
   **29 passed, 0 failed**.
4. Same full-suite command, run 2: exit 0, **29 passed, 0 failed**.

Existing tap/hit-test warnings remain nonfatal in both test runs. Test
assertions were not weakened. Two passes provide repeatability evidence,
not proof that all possible flakes are absent. `git diff --check` passed.

## Source-level toolchain evidence and limits

Searched the entire installed `packages/flutter_tools/gradle/` tree using
`rg -n --hidden --no-ignore 'project\s*\.\s*exec\b'`: no matches (exit 1).
The same search in `packages/flutter_tools/lib/src/android/` found no matches.
`gradle/src/main/kotlin/FlutterPlugin.kt:277-278` obtains ExecOperations
and calls `execOps.exec`, rather than the removed Project.exec API.

Installed `lib/src/android/gradle_utils.dart` establishes template defaults:
Gradle **9.5.0** (:34), AGP **9.3.1** (:40-41), KGP **2.4.20** (:47),
compileSdk **36** (:56), targetSdk **36** (:60).
`gradle/src/main/kotlin/FlutterExtension.kt:23` also sets compileSdk 36.
Thus the old Project.exec source obstacle is absent and app compileSdk is
explicitly 37. **The app's complete Android toolchain is not yet validated.**
Existing app pins remain AGP 8.1.0, Gradle 8.3, KGP 1.8.22; SDK template
versions do not automatically replace existing app pins. These must be
upgraded and Kotlin/plugin migration assessed as part of the next CI work.
A real Gradle 9 build is deferred to CI; no Gradle/APK command ran on this VM.

No blocker remains for this step's Dart analyze/test acceptance. No push,
PC access, credential access, SDK commit or build output commit occurred.

## Next step and usage reporting

Return to direction A: prepare a separate CI workflow for FreeRDP 3.33.0
AAR packaging and Flutter plugin integration, upgrade the consuming Android
toolchain with the official AGP 9/Kotlin migration guide, then validate actual
Gradle 9 builds on CI and runtime on an Android device. Planning estimate:
2–4 working days, conditional on CI packaging and plugin migration results.

Final current-session CLI `tokens used` is unavailable while this response
is running. Read that exact counter from the completed CLI log; no historical
or live token_count snapshot is substituted.

---

# Bước 5 — blocked by default compileSdk requirement

2026-11-13: Latest stable verified from the official release manifest is
Flutter **3.50.0**. Official release notes and tagged source specify
AGP **9.3.1**, Gradle **9.5.0**, default compileSdk **36**, below the requested
minimum **37**. Stopped before installing a nonqualifying SDK.

Full sources, command evidence, blocker and next steps:
[Step 5 log](rdp-step5-flutter-upgrade-log.md).
No new SDK installed; analyze/test not run (0 tests executed).
New-SDK project.exec status is unverified. Toolchain unblock is not claimed;
a real Gradle 9 build still requires future CI validation.
Next: resolve the default compileSdk constraint, then separate SDK installation
and app validation before direction A CI AAR/plugin work.

---

# Step 4 — direction A: stopped before implementation

Date: 2026-11-13. Branch: `rdp-prototype`; starting HEAD:
`b65ce5e8f43f4fc19726470480bf199f91c11536`.

**Incomplete. No new workflow, AAR dependency, PlatformView or layout change was
created.** This is not evidence that direction A is impossible. The requested
end-to-end toolchain compatibility remains unresolved; no CI run was made.

## Evidence and unresolved compatibility gate

Read the full existing status, feasibility brief, existing release workflow,
app Gradle/settings/wrapper, Dart UI/tests, upstream Studio Gradle files,
manifest and `LibFreeRDP.java` before considering implementation.
Upstream source root: `/home/hatch/workspace/FreeRDP-3.33.0/`; Studio paths below
are relative to `client/Android/Studio/`.

- `build.gradle:10,15,44-54`: AGP 9.2.1, androidgitversion 0.4.14, SDK 37,
  Build Tools 37.0.0, minSdk 29, default NDK 29.0.13113456, CMake 4.1.2.
  `gradle/wrapper/gradle-wrapper.properties:3`: Gradle 9.6.1.
- `freeRDPCore/build.gradle:68-80`: implementation dependencies include
  AppCompat 1.7.1, Core 1.19.0, Preference 1.2.1, RecyclerView 1.4.0,
  Lifecycle 2.11.0, Room runtime 2.8.4, SQLCipher 4.17.0, SQLite 2.7.0.
  Copying a standalone AAR into `libs/` does not copy its Maven dependency
  metadata; the consuming app must supply those dependencies separately.
- App `android/settings.gradle:21-22`: AGP 8.1.0, Kotlin 1.8.22.
  App wrapper: Gradle 8.3. `android/app/build.gradle:10,24`: Flutter compileSdk,
  minSdk 23. Local Flutter `packages/flutter_tools/gradle/src/main/groovy/
  flutter.groovy:45` sets compileSdk 34. Raising minSdk to 29 alone does not
  establish compile/dependency compatibility.
- Android's published API support table specifies AGP >= 9.1.1 for API 37:
  https://developer.android.com/build/releases/about-agp#api-level-support
- Local Flutter 3.24.5 `flutter.groovy:1687` calls `project.exec` unconditionally
  while assembling Flutter artifacts. Gradle 9 removed `Project.exec(Closure)`:
  https://docs.gradle.org/current/userguide/upgrading_major_version_9.html#removed_project_exec
  Thus simply moving the Flutter app onto upstream's Gradle 9.6.1 toolchain
  is not a compatible fix without further Flutter build integration changes.
  FreeRDP's own Gradle build and the app build are separate: FreeRDP using
  Gradle 9 does NOT, by itself, require the app to use Gradle 9.

The exact consuming compileSdk/AGP/Kotlin requirements of the published
AndroidX artifacts were **not verified**. Do not treat them as proven to require
API 37, or claim an unavoidable Flutter/FreeRDP incompatibility from the above.
Attempt to retrieve Core's AAR metadata:

```sh
curl -fL --connect-timeout 10 --max-time 25 \
  https://dl.google.com/dl/android/maven2/androidx/core/core/1.19.0/core-1.19.0.aar \
  -o /tmp/ace-core-1.19.0.aar
```

Exit 7: `Failed to connect to hatch-egress-proxy port 3128`. Web documentation
was readable but did not establish these exact published artifact requirements.
Stopped under the request's missing-information/no-guessing gate rather than
selecting unverified dependency downgrades or modifying the pinned Flutter SDK.

`LibFreeRDP.java:136-179` declares native methods **private**. Public wrappers
include `hasH264Support()` (:126), `newInstance(Context)` (:186) and
`freeInstance(long)` (:191). Future Kotlin integration must use public wrappers,
not invoke the private JNI methods directly. A waiting placeholder need not
create an RDP instance. No native load/no-crash runtime result is claimed.

## VM validation: blocked before execution

Both requested local SDK commands were attempted, with no SDK copy:

```sh
/home/hatch/workspace/flutter/bin/flutter analyze --no-pub
/home/hatch/workspace/flutter/bin/flutter test --no-pub
```

Both exited **1** before running analysis/tests:

```text
Cannot open file, path = '/home/hatch/workspace/flutter/bin/cache/lockfile'
(OS Error: Read-only file system, errno = 30)
```

Current sandbox allows writes only to this app and `/tmp`; approval is disabled.
Analyze issue count: **unavailable**. Tests executed: **0**; pass/fail unavailable.
Historical passing results below are not results of this attempt.
No Gradle command, APK build, PC access, credentials, push, release or Firebase
upload was performed. `build-apk.yml`, `lib/agent.dart`, minSdk and keyboard
remain unchanged. No generated binary was added to git.

## Resume requirements and future CI scope

First inspect resolved AAR metadata/POM/Kotlin metadata with functioning Maven
access and establish a compatible app build configuration under Flutter 3.24.5,
or explicitly change the Flutter/toolchain constraint. Restore write access to
the existing Flutter cache for the mandatory VM validation.

Then implement the separate push-to-`rdp-prototype`/manual CI workflow: shallow
clone tag 3.33.0, verify commit and tag, provision SDK 37 / Build Tools 37.0.0 /
CMake 4.1.2 / JDK 17, download checksum-verified NDK r29 29.0.14206865 using the
URL/hash already recorded below, write matching `release.properties`, assemble
`:freeRDPCore:assembleQa`, copy `freeRDPCore-qa.aar` into app libs, resolve app
dependencies, build with Flutter 3.24.5 and upload AAR/APK artifacts only.
No such workflow exists yet, so pushing this documentation commit does not run
that validation. AAR/APK compilation and Android runtime behavior remain
unverified. Tool availability, shallow-clone versioning and minSdk/manifest
merging must also be checked there.

After packaging/integration: exact 50/50 RdpView/unchanged laptop keyboard,
physical viewport dimensions (logical times devicePixelRatio), real RDP
connection/render lifecycle, JNI input and NLA, then Fold device validation.
Earlier 2–4 working day estimate for that integration is a planning estimate
after toolchain unblock; unblock duration is unknown.

CLI log snapshot (not final turn usage):
`/home/hatch/.codex/sessions/2026/11/13/rollout-2026-11-13T12-23-20-01a1d4dc-bef5-7fc0-bfe7-d283c028eb81.jsonl`,
last observed `token_count` at `2026-11-13T12:25:28.818Z`: total 655,548
(input 652,200 including cached input 589,184; output 3,348).
A completed current-turn total is not available here; this snapshot must not be
presented as the final total for this attempt.

---

# Step 3 — callback gate: STOP under the primitive/String-only contract

Date: 2026-11-13. Branch: `rdp-prototype`; starting HEAD: `31c55fa`.

**Direction B is NOT feasible under the exact requested type restriction. Stopped
at step 1.** This does not mean a standalone Java bridge is inherently impossible.
The blocker is the immutable native ABI's mutable `StringBuilder` authentication
parameters, not AndroidX, resources, Activity, BookmarkBase or SessionState.

`android_freerdp.c:497-520` creates three `java/lang/StringBuilder` objects,
passes them to the authentication callback, and reads their mutated contents back
when it returns true. `android_freerdp.c:537,541-542` selects `OnAuthenticate`
(NLA/TLS/RDP) or `OnGatewayAuthenticate` (gateway). Both require exactly:

```text
(JLjava/lang/StringBuilder;Ljava/lang/StringBuilder;Ljava/lang/StringBuilder;)Z
```

These object parameters cannot be changed to primitive/String with the supplied
native binary: GetStaticMethodID resolves the entire descriptor. Even a stub
returning false must retain StringBuilder parameters. StringBuilder is standard
Java and would compile without AndroidX, but allowing `java.*` imports does not
make it a primitive/String callback. No upstream source or binary was modified.
There are also primitive-array callback descriptors and Context/Bitmap native
entry points outside a literal primitive/String-only interface (listed below).

## Evidence scope and commands

All source references below are relative to
`/home/hatch/workspace/FreeRDP-3.33.0/client/Android/Studio/freeRDPCore/src/main/cpp/`
unless stated otherwise. Read callback `.c/.h`, JNI header, freerdp, event, disp,
cliprdr and JNI utils; searched **all** native sources excluding `external/`,
including RAIL. `android_event.c` and `android_disp.c` contain no Java lookup or
callback invocation. Commands executed:

```sh
rg -n 'FindClass|Get(MethodID|StaticMethodID)|Call\w*Method' /home/hatch/workspace/FreeRDP-3.33.0/client/Android/Studio/freeRDPCore/src/main/cpp --glob '!**/external/**'
rg -n 'freerdp_callback|JAVA_.*CLASS' /home/hatch/workspace/FreeRDP-3.33.0/client/Android/Studio/freeRDPCore/src/main/cpp --glob '!**/external/**'
nm -D /home/hatch/workspace/freerdp-build-arm64/libfreerdp-android.so | grep Java_
```

## Every FindClass and instance GetMethodID

| Class (full JNI name) | FindClass evidence | Instance method lookup |
| --- | --- | --- |
| `com/freerdp/freerdpcore/services/LibFreeRDP` | `android_jni_callback.c:33` via path at `:25,67`; `android_freerdp.c:1333`; macro `android_freerdp_jni.h:23` | `<init>()V`, `android_jni_callback.c:41` |
| `android/content/Context` | `android_freerdp.c:814`; macro `android_freerdp_jni.h:24` | `getFilesDir()Ljava/io/File;`, `android_freerdp.c:825` |
| `java/io/File` | `android_freerdp.c:815`; macro `android_freerdp_jni.h:25` | `getAbsolutePath()Ljava/lang/String;`, `android_freerdp.c:834` |
| `java/lang/StringBuilder` | `android_jni_utils.c:48,88` | `<init>(Ljava/lang/String;)V` at `:55`; `<init>()V` at `:68`; `toString()Ljava/lang/String;` at `:93` |

No other app-owned Java class is looked up. Context, File and StringBuilder are
provided by Android/Java; no additional app stub class is required. LibFreeRDP
requires an accessible zero-argument constructor (`NewObject` at
`android_jni_callback.c:49`). StringBuilder construction uses `NewObject` at
`android_jni_utils.c:64,73`.

## Every static callback lookup and invocation

All following callbacks are static methods on
`com/freerdp/freerdpcore/services/LibFreeRDP` (not an Activity despite the C
variable name). The table gives the full JNI descriptor and caller evidence.
The generic dispatch uses GetObjectClass of `jLibFreeRDPObject`, created at
`android_jni_callback.c:49,58,67`; GetStaticMethodID at `:114,148,184`, followed
by CallStaticVoidMethodV at `:122`, CallStaticBooleanMethodV at `:156`, or
CallStaticIntMethodV at `:192`. Wrappers at `:202-226` route void/bool/int.

| Callback | Full JNI descriptor | Caller evidence |
| --- | --- | --- |
| `OnRemoteClipboardChanged` | `(JLjava/lang/String;)V` | `android_cliprdr.c:464` |
| `OnRemoteClipboardImageChanged` | `(J[B)V` | `android_cliprdr.c:489` |
| `OnGraphicsUpdate` | `(JIIII)V` | `android_freerdp.c:199` |
| `OnGraphicsResize` | `(JIII)V` | `android_freerdp.c:219` |
| `OnPreConnect` | `(J)V` | `android_freerdp.c:252` |
| `OnPointerSetNull` | `(J)V` | `android_freerdp.c:347` |
| `OnPointerSetDefault` | `(J)V` | `android_freerdp.c:355` |
| `OnExperimentalFeature` | `(JI)Z` | `android_freerdp.c:454`, `android_freerdp.c:459` |
| `OnSettingsChanged` | `(JIII)V` | `android_freerdp.c:472` |
| `OnConnectionSuccess` | `(J)V` | `android_freerdp.c:476` |
| `OnDisconnecting` | `(J)V` | `android_freerdp.c:482` |
| `OnVerifyCertificateEx` | `(JLjava/lang/String;JLjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;J)I` | `android_freerdp.c:567` |
| `OnVerifyChangedCertificateEx` | `(JLjava/lang/String;JLjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;J)I` | `android_freerdp.c:596` |
| `OnReconnecting` | `(J)V` | `android_freerdp.c:630` |
| `OnDisconnected` | `(J)V` | `android_freerdp.c:733` |
| `OnConnectionFailure` | `(J)V` | `android_freerdp.c:735` |
| `OnRailMonitoredDesktop` | `(J[JJ)V` | `android_rail.c:84` |
| `OnRailWindowMove` | `(JJIIII)V` | `android_rail.c:134`, `android_rail.c:218`, `android_rail.c:231`, `android_rail.c:237` |
| `OnRailSessionEnd` | `(J)V` | `android_rail.c:192` |
| `OnRailWindowHide` | `(JJ)V` | `android_rail.c:209` |
| `OnRailWindowDestroy` | `(JJ)V` | `android_rail.c:251` |
| `OnAuthenticate` | `(JLjava/lang/StringBuilder;Ljava/lang/StringBuilder;Ljava/lang/StringBuilder;)Z` | `android_freerdp.c:506-510,537,541-542` |
| `OnGatewayAuthenticate` | `(JLjava/lang/StringBuilder;Ljava/lang/StringBuilder;Ljava/lang/StringBuilder;)Z` | `android_freerdp.c:506-510,537,541-542` |
| `OnPointerSet` | `(J[IIIII)V` | lookup `android_freerdp.c:1344`; CallStaticVoidMethod `:325` |
| `OnRailWindowUpdate` | `(JJII[I)V` | lookup `android_freerdp.c:1346`; CallStaticVoidMethod `:411` |

The two direct CallStaticVoidMethod calls use global class `gJavaActivityClass`
created from LibFreeRDP at `android_freerdp.c:1333,1342`, with cached method IDs.
OnRailWindowUpdate lookup failure is cleared at `:1347-1350`; it is still listed
because native attempts it.

Every nonstatic Call*Method is CallObjectMethod:

- `android_freerdp.c:842`: `Context.getFilesDir()Ljava/io/File;` on the `context`
  argument of `freerdp_new`.
- `android_freerdp.c:850`: `File.getAbsolutePath()Ljava/lang/String;` on the
  returned `filesDirObj`.
- `android_jni_utils.c:98`: `StringBuilder.toString()Ljava/lang/String;` on
  each `strBuilder` passed to the readback helper.

## Complete exported JNI inventory and Java declarations

`nm` returned the following **21** symbols (exit 0). All use the prefix
`Java_com_freerdp_freerdpcore_services_LibFreeRDP_`. `_1` encodes a literal
underscore. **None has a `__` overload suffix, so no parameter/return signature
is encoded in these short JNI symbol names.** Signatures must be checked from
source, not inferred from nm. Callback methods are Java methods looked up at
runtime, not exported native functions; nm alone does not validate callbacks.

```text
00000000000072bc T Java_com_freerdp_freerdpcore_services_LibFreeRDP_freerdp_1connect
0000000000007620 T Java_com_freerdp_freerdpcore_services_LibFreeRDP_freerdp_1disconnect
000000000000706c T Java_com_freerdp_freerdpcore_services_LibFreeRDP_freerdp_1free
0000000000007f7c T Java_com_freerdp_freerdpcore_services_LibFreeRDP_freerdp_1get_1build_1config
0000000000007f44 T Java_com_freerdp_freerdpcore_services_LibFreeRDP_freerdp_1get_1build_1revision
0000000000007eb0 T Java_com_freerdp_freerdpcore_services_LibFreeRDP_freerdp_1get_1jni_1version
00000000000070d8 T Java_com_freerdp_freerdpcore_services_LibFreeRDP_freerdp_1get_1last_1error_1string
0000000000007f0c T Java_com_freerdp_freerdpcore_services_LibFreeRDP_freerdp_1get_1version
0000000000007ee8 T Java_com_freerdp_freerdpcore_services_LibFreeRDP_freerdp_1has_1camera_1redirection
0000000000007ec4 T Java_com_freerdp_freerdpcore_services_LibFreeRDP_freerdp_1has_1h264
0000000000007ab0 T Java_com_freerdp_freerdpcore_services_LibFreeRDP_freerdp_1is_1unicode_1input_1supported
0000000000006c40 T Java_com_freerdp_freerdpcore_services_LibFreeRDP_freerdp_1new
0000000000007138 T Java_com_freerdp_freerdpcore_services_LibFreeRDP_freerdp_1parse_1arguments
0000000000007b94 T Java_com_freerdp_freerdpcore_services_LibFreeRDP_freerdp_1send_1clipboard_1data
0000000000007cf0 T Java_com_freerdp_freerdpcore_services_LibFreeRDP_freerdp_1send_1clipboard_1image_1data
0000000000007aec T Java_com_freerdp_freerdpcore_services_LibFreeRDP_freerdp_1send_1cursor_1event
0000000000007930 T Java_com_freerdp_freerdpcore_services_LibFreeRDP_freerdp_1send_1key_1event
0000000000007e78 T Java_com_freerdp_freerdpcore_services_LibFreeRDP_freerdp_1send_1monitor_1layout
00000000000079f8 T Java_com_freerdp_freerdpcore_services_LibFreeRDP_freerdp_1send_1unicodekey_1event
000000000000707c T Java_com_freerdp_freerdpcore_services_LibFreeRDP_freerdp_1set_1foreground
000000000000773c T Java_com_freerdp_freerdpcore_services_LibFreeRDP_freerdp_1update_1graphics
```

Java declaration evidence (upstream `src/main/java/com/freerdp/freerdpcore/services/LibFreeRDP.java`):

| Line | Java declaration | Strict primitive/String only |
| --- | --- | --- |
| 136 | `boolean freerdp_has_h264();` | yes |
| 138 | `boolean freerdp_has_camera_redirection();` | yes |
| 140 | `String freerdp_get_jni_version();` | yes |
| 142 | `String freerdp_get_version();` | yes |
| 144 | `String freerdp_get_build_revision();` | yes |
| 146 | `String freerdp_get_build_config();` | yes |
| 148 | `long freerdp_new(Context context);` | no |
| 150 | `void freerdp_free(long inst);` | yes |
| 152 | `boolean freerdp_parse_arguments(long inst, String[] args);` | no |
| 154 | `boolean freerdp_connect(long inst);` | yes |
| 156 | `boolean freerdp_disconnect(long inst);` | yes |
| 158 | `void freerdp_set_foreground(long inst, boolean foreground);` | yes |
| 160 | `boolean freerdp_update_graphics(long inst, Bitmap bitmap, int x, int y, int width, int height);` | no |
| 163 | `boolean freerdp_send_cursor_event(long inst, int x, int y, int flags);` | yes |
| 165 | `boolean freerdp_send_key_event(long inst, int keycode, boolean down);` | yes |
| 167 | `boolean freerdp_send_unicodekey_event(long inst, int keycode, boolean down);` | yes |
| 170 | `boolean freerdp_is_unicode_input_supported(long inst);` | yes |
| 172 | `boolean freerdp_send_clipboard_data(long inst, String data);` | yes |
| 174 | `boolean freerdp_send_clipboard_image_data(long inst, byte[] data, String mimeType);` | no |
| 177 | `boolean freerdp_send_monitor_layout(long inst, int width, int height);` | yes |
| 179 | `String freerdp_get_last_error_string(long inst);` | yes |

Thus the 17 declarations marked yes are the primitive/String subset, but they
cannot form the requested functional bridge: instance creation requires
`freerdp_new(Context)`, graphics copy uses `freerdp_update_graphics(... Bitmap ...)`,
and required authentication callbacks need StringBuilder. There is no exported
primitive/String replacement for those object paths. This inventory is an audit,
not a claim that a bridge was compiled or packaged.

## Stop outcome, deliverables and next step

Only this status document changed. No bridge source, classes.jar, AAR, plugin,
PlatformView, layout, Gradle dependency or tests were added. AAR SHA256: **N/A**.
No javac, Gradle, APK, Flutter analyze/test, device/PC access, credentials or push
was run in step 3. Tests executed this attempt: **0** (pass/fail: N/A); analyze
issue count: **N/A**. Earlier analyze/test results below are historical.
The requested 50/50 layout and physical-pixel RDP resolution remain pending.

Proposed scope change for a future attempt: allow the exact standard Java
StringBuilder and primitive-array callback descriptors, plus Android SDK Context
and Bitmap native parameters. That route needs no AndroidX/UI/R based on this
lookup audit, but has NOT been implemented or runtime-validated. After that,
compile/package the bridge, integrate lifecycle/PlatformView and exact 50/50
layout, then real RDP resolution, JNI input and NLA/device validation. Planning
estimate: **2–4 working days after the ABI type constraint is resolved**, not a
verified duration. No automatic workaround was attempted past the stop gate.

Final Codex CLI `tokens used` is unavailable to this active turn; a live counter
would not be the final total. The caller must take that value from the completed
CLI log. No token total is invented here.

---

# Step 2 — manual AAR blocked by Java dependency closure

Date: 2026-11-13. Branch: `rdp-prototype`; starting HEAD: `ffbc3c8`.

**Stopped at the AAR gate as requested. No AAR, classes.jar, plugin,
PlatformView, Dart/layout changes, or Gradle dependency was added.**
No Gradle, APK build, PC access, credentials, or push was used.
Flutter analyze/test were not run in this attempt; tests executed: **0**.
The 29 passing tests recorded below belong to the previous attempt.

## Evidence

`nm -D /home/hatch/workspace/freerdp-build-arm64/libfreerdp-android.so`
confirms exported `Java_com_freerdp_freerdpcore_services_LibFreeRDP_*`
symbols. The required Java bridge cannot be replaced by a differently named
class. Upstream sources were read without modification; no AndroidX stubs
were created.

No `.jar`/`.aar` dependency artifacts were found by searching
`/home/hatch/.gradle`. Download attempted:

```sh
curl -fL --connect-timeout 15 --max-time 45 \
  https://dl.google.com/dl/android/maven2/androidx/collection/collection/1.2.0/collection-1.2.0.jar \
  -o /tmp/ace-rdp-step2/collection-1.2.0.jar
```

Exit **7**:

```text
curl: (7) Failed to connect to hatch-egress-proxy port 3128 after 0 ms: Couldn't connect to server
```

Direct compilation of the bridge with source lookup for its referenced classes:

```sh
/home/hatch/workspace/jdk17/bin/javac \
  -classpath /home/hatch/workspace/android-sdk/platforms/android-34/android.jar \
  -sourcepath /home/hatch/workspace/FreeRDP-3.33.0/client/Android/Studio/freeRDPCore/src/main/java \
  -d /tmp/ace-rdp-step2/classes -Xmaxerrs 20 \
  /home/hatch/workspace/FreeRDP-3.33.0/client/Android/Studio/freeRDPCore/src/main/java/com/freerdp/freerdpcore/services/LibFreeRDP.java
```

`javac` failed; diagnostic log: `/tmp/ace-rdp-step2/javac.log`.
The first 20 of **193 total errors** include:

- `LibFreeRDP.java`: `package androidx.collection does not exist`;
  `LongSparseArray` unresolved.
- `BookmarkBase.java`: `androidx.annotation.NonNull` unresolved.
- `GlobalApp.java`: `androidx.appcompat.app` and
  `androidx.core.content` packages missing.
- `PrintJobMonitor.java`, pulled in by `GlobalApp`: `Nullable` unresolved.
- `ApplicationSettingsActivity.java`: AppCompat and AndroidX Preference
  packages missing (`AppCompatActivity`, `PreferenceFragmentCompat`, etc.),
  plus `com.freerdp.freerdpcore.R` unresolved. This is a resource-bearing UI
  dependency, so obtaining Collection alone would not complete the closure.

AAR packaging/structure checks, AAR SHA256, native dependency closure packaging,
and plugin javac validation are **not available** because compilation failed
before `classes.jar` creation. No partial AAR was installed in the app.

## Remaining work

Restore Maven dependency access and explicitly resolve the upstream UI/resource
closure before retrying packaging, or agree on a separate JNI bridge extraction
that preserves every required native method and callback signature. Neither
route has been implemented or validated here.
After the AAR gate: Java PlatformView and channel, exact 50/50 layout with the
existing keyboard, physical viewport dimensions (logical × devicePixelRatio),
then real RDP/surface lifecycle, JNI input, and NLA/device verification.
Planning estimate after packaging is unblocked: **2–4 working days**;
packaging unblock time remains unknown.

Token usage must come from the current Codex JSONL `token_count` event; any
live reading is a snapshot, not the completed turn total. No estimated token
count is recorded here.

---

# RDP prototype — round 2: native succeeds, AAR blocked

Date: 2026-11-13. Branch: `rdp-prototype`; starting commit: `61496cf`.

## Verified result

FreeRDP Android JNI and its dependencies built successfully for **arm64-v8a
only**, Release, Android API 29. CMake configure and build both exited 0.
`llvm-readelf -h` confirms the JNI library is ELF64, AArch64.
**No AAR was produced. No Flutter plugin/PlatformView was added.**
Runtime surface visibility and no-crash behavior remain unverified.
No APK task, device/PC connection, credentials, or push was used.
The existing Flutter keyboard and app source are unchanged.

## Source and toolchain

- Source: `/home/hatch/workspace/FreeRDP-3.33.0`.
- Tag: `3.33.0`; commit: `5a10d7b6b79a2fbc62e8eba77085cd356dc303a6`.
  Tracked upstream source was not modified.
- This tag does **not** contain `scripts/android-build-freerdp.sh`.
  The actual route is `client/Android/Studio/freeRDPCore/src/main/cpp/CMakeLists.txt`
  and `client/Android/cmake/ExternalDeps.cmake`.
- Dependencies built from upstream's hash-checked URLs: OpenSSL `4.0.1`,
  cJSON `1.7.19`, uriparser `1.0.2`. Extra codecs disabled per QA configuration.
- NDK: `/home/hatch/workspace/android-ndk-r29`, revision **29.0.14206865**,
  Clang 21.0.0. This differs from upstream's default `29.0.13113456`.
- CMake: **3.28.3**, Unix Makefiles; native target API **29**.
- Installed SDK: `/home/hatch/workspace/android-sdk`, platform **android-34**,
  Build Tools **34.0.0**. CMake native build uses NDK API headers, not SDK 34.
- JDK: `/home/hatch/workspace/jdk17`, Temurin **17.0.21+9**.
- AAR attempt: upstream wrapper **Gradle 9.6.1**; build file declares
  **AGP 9.2.1**, compile/target SDK **37**, Build Tools **37.0.0**,
  CMake **4.1.2**, default multiple ABIs. These defaults were NOT provisioned
  or validated: Gradle stalled before project configuration. A future AAR run
  must set `release.properties` with `ABI_FILTERS=arm64-v8a`, matching split
  settings, installed NDK/CMake versions, and a compatible SDK/dependency set.

`sdkmanager` installation of `ndk;29.0.13113456` failed to fetch manifests,
including with explicit proxy options (`Failed to download any source lists!`,
`IO exception while downloading manifest`, `Failed to find package`).
Direct curl download succeeded instead:

```sh
git clone --depth 1 --branch 3.33.0 https://github.com/FreeRDP/FreeRDP.git /home/hatch/workspace/FreeRDP-3.33.0
curl -fL --connect-timeout 15 --max-time 300 https://dl.google.com/android/repository/android-ndk-r29-linux.zip -o /home/hatch/workspace/android-ndk-r29-linux.zip
unzip -q /home/hatch/workspace/android-ndk-r29-linux.zip -d /home/hatch/workspace
```

Downloaded NDK archive SHA256:
`4abbbcdc842f3d4879206e9695d52709603e52dd68d3c1fff04b3b5e7a308ecf`.

## Native commands executed

```sh
cmake -S /home/hatch/workspace/FreeRDP-3.33.0/client/Android/Studio/freeRDPCore/src/main/cpp \
  -B /home/hatch/workspace/freerdp-build-arm64 \
  -DCMAKE_TOOLCHAIN_FILE=/home/hatch/workspace/android-ndk-r29/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-29 \
  -DCMAKE_BUILD_TYPE=Release \
  -DWITH_FFMPEG=OFF -DWITH_OPENH264=OFF -DWITH_OPUS=OFF \
  -DWITH_WEBP=OFF -DWITH_JPEG=OFF -DWITH_PNG=OFF \
  -DWITH_CJSON=ON -DWITH_OPENSSL=ON
cmake --build /home/hatch/workspace/freerdp-build-arm64 --parallel 2
```

Final build output:

```text
[100%] Linking C shared library libfreerdp-android.so
[100%] Built target freerdp-android
```

Upstream OpenSSL internally invokes unbounded `make -j`, despite outer
`--parallel 2`; it completed in this attempt, but consumed substantial memory.

Uncommitted artifacts retained outside this app repository:

- JNI: `/home/hatch/workspace/freerdp-build-arm64/libfreerdp-android.so` (481 KiB).
  SHA256: `eee37022156c55589363307297d4edf2b0561bfe07b66da8b81a3df3bc35db2e`.
- FreeRDP, WinPR, OpenSSL, cJSON, uriparser libraries:
  `/home/hatch/workspace/FreeRDP-3.33.0/client/Android/Studio/freeRDPCore/src/main/jniLibs/arm64-v8a/`.
- **AAR: none.**

## AAR blocker and stop

Command executed from `/home/hatch/workspace/FreeRDP-3.33.0/client/Android/Studio`:

```sh
JAVA_HOME=/home/hatch/workspace/jdk17 \
ANDROID_HOME=/home/hatch/workspace/android-sdk \
./gradlew --no-daemon :freeRDPCore:assembleQa
```

Gradle downloaded successfully, then forked a single-use daemon despite
`--no-daemon`. Daemon PID 27493 advertised `127.0.0.1:39115` at 11:52:19 UTC,
received no build request, and exited at 11:54:19 UTC:

```text
Marking daemon stopped due to after being idle for 2 minutes. The daemon is not running a build
```

Client PID 26352 remained blocked. `jstack` showed:

```text
at org.gradle.internal.remote.internal.inet.SocketConnection$SocketInputStream.read(SocketConnection.java:187)
at org.gradle.internal.remote.internal.inet.SocketConnection.receive(SocketConnection.java:83)
at org.gradle.launcher.daemon.client.DaemonClientConnection.receive(DaemonClientConnection.java:82)
at org.gradle.launcher.daemon.client.DaemonClient.executeBuild(DaemonClient.java:189)
```

This is consistent with the known VM localhost transport restriction; the
observed failure is stalled client/daemon communication, not a C compile error.
The stalled wrapper was terminated with SIGTERM (exit **143**); Gradle did not
return a normal build-failure diagnostic. No packaging task executed.
Stopped here instead of creating an unbuildable app integration or claiming AAR
success. Only one native toolchain/configuration and one AAR task were attempted.

Full logs remain outside the repository under
`/home/hatch/workspace/ace-remote/briefs/`:

- `rdp-v2-cmake-configure.log`, `rdp-v2-native-build.log`
- `rdp-v2-aar.log`, `rdp-v2-gradle-daemon.log`, `rdp-v2-gradle-client-stack.log`
- `rdp-v2-ndk.log`, `rdp-v2-ndk-proxy.log`, `rdp-v2-ndk-curl.log`
- `rdp-v2-analyze.log`, `rdp-v2-test.log`

## Flutter validation and next work

Using `/home/hatch/workspace/flutter/bin/flutter` in place:

- `flutter analyze --no-pub`: exit 0, **No issues found**.
- `flutter test --no-pub`: exit 0, **29 passed, 0 failed**.
  Existing hit-test warnings are present; suite still passes.

First unblock AAR packaging on an environment with working Gradle transport,
provision compatible Android build tools, and enforce arm64-only settings.
Then add the platform channel and actual FreeRDP view, reuse the existing
Flutter keyboard below it, and test lifecycle/no-crash on Fold6.
The remote viewport and keyboard must each occupy exactly 50% of available
content height. Negotiate the RDP session resolution from the top viewport's
physical pixel width/height (logical size × device pixel ratio); do not fit a
1920×1080 session into it.

After that: real RDP lifecycle/connection, JNI keyboard/mouse, NLA authentication
without persisting secrets. Planning estimate after toolchain unblock: **2–4
working days**, including device validation; packaging unblock duration unknown.

Exact round-2 token usage is not exposed by the session's available tools.
Do not infer it from the live log or report an invented number; the coordinator
must take the final `tokens used` counter from the completed Codex CLI log.
Round 1's 17,366 tokens are separate.

---

# RDP prototype — blocked before native build

Date: 2026-11-13. Branch: `rdp-prototype`; starting commit: `c0f6e19`.

## Scope and layout

Keep the existing Flutter laptop keyboard unchanged in the bottom 50%.
The top 50% must host the FreeRDP surface through an Android PlatformView,
with a platform channel for lifecycle and, later, JNI input.
When connecting, request the RDP session resolution using the measured top
surface's physical pixel dimensions (logical dimensions × device pixel ratio).
Do not start with the PC's 1920×1080 resolution and scale it: the negotiated
session must match the surface to fill it without borders, cropping or distortion.
No credentials, PC access, APK build or RDP connection were used in this attempt.

## Verified local environment

- Flutter SDK: `/home/hatch/workspace/flutter` (used in place).
- Android SDK: `/home/hatch/workspace/android-sdk`, found via `android/local.properties`.
- Installed SDK platform: `android-34`; Build Tools: `34.0.0`.
- Android command-line tools: `12.0`.
- NDK: absent; no version installed or used.
- CMake: `3.28.3`.
- `ANDROID_HOME` and `ANDROID_SDK_ROOT`: unset.
- `/home/hatch`: approximately 140 GiB available; `/tmp`: 512 MiB.

## Research and download blocker

Candidate source: FreeRDP tag `3.33.0`. Source was NOT downloaded, pinned to a
commit or built. No native/AAR build command ran; no AAR was produced.

The web tool could read these upstream files:

- https://raw.githubusercontent.com/FreeRDP/FreeRDP/3.33.0/client/Android/Studio/freeRDPCore/build.gradle
- https://raw.githubusercontent.com/FreeRDP/FreeRDP/3.33.0/client/Android/Studio/build.gradle

The module applies `com.android.library`, builds JNI through
`src/main/cpp/CMakeLists.txt`, and supports an `ABI_FILTERS` configuration.
Its QA configuration specifies arm64-v8a and enables OpenSSL and cJSON.
The top-level file reports defaults NDK `29.0.13113456`, SDK/build-tools `37` /
`37.0.0`, CMake `4.1.2`, and AGP `9.2.1`. These are remote file contents,
not a tested toolchain recommendation; local CMake 3.28.3 compatibility is unverified.
Dependency versions and the Android build script could not be inspected completely:
the web tool returned `Cache miss` for `scripts/android-build-freerdp.sh`.

Commands attempted in the VM:

```sh
curl -IL --max-time 20 https://github.com/FreeRDP/FreeRDP/releases/tag/3.33.0
```

Result: exit 7, `Failed to connect to hatch-egress-proxy port 3128`.

```sh
curl --noproxy '*' -IL --connect-timeout 10 --max-time 15 https://github.com/FreeRDP/FreeRDP/archive/refs/tags/3.33.0.tar.gz
```

Result: exit 6, `Could not resolve host: github.com`.

Stopped before downloading source, installing NDK, or changing app/plugin code.
There is no evidence yet that the native build succeeds or fails to compile.

## Flutter validation blocker

Both commands were attempted against the unchanged application:

```sh
/home/hatch/workspace/flutter/bin/flutter analyze --no-pub
/home/hatch/workspace/flutter/bin/flutter test --no-pub
```

Both exited 1 before analysis or test execution:

```text
Failed to open or create the artifact cache lockfile:
FileSystemException: Cannot open file,
path = '/home/hatch/workspace/flutter/bin/cache/lockfile'
(OS Error: Read-only file system, errno = 30)
```

Analysis issue count: unavailable. Tests executed: 0; pass/fail: unavailable.
The current sandbox only permits writes inside the app and `/tmp`, so SDK cache
writes and installation directly under `~/workspace/` are not permitted.
The Flutter SDK was not copied and no permissions were changed.

## Resume requirements

Restore VM download connectivity and allow writes to the existing Flutter cache
and a toolchain directory under `~/workspace/`. Then inspect/pin upstream source
and dependencies, build only arm64-v8a native/AAR, and proceed with the 50/50
PlatformView integration after the native build succeeds. Do not build an APK.
Runtime surface/no-crash behavior still requires an Android device run later.

After this prototype is validated, proposed work is real RDP connection and
surface lifecycle, JNI keyboard/mouse input, then NLA credential handling without
persisting secrets. Planning estimate: 2–4 working days including Fold6 testing,
subject to native integration results; this is not a measured completion time.

Exact session token usage is not exposed by the available tools; it cannot be
reported accurately from this environment.
