# Step 7b — CI packaging and waiting PlatformView

2026-11-13, branch `rdp-prototype`, base `c971db2`.

Read `git show c971db2` and the four current Android toolchain files:
AGP 9.3.1 / Gradle 9.5.0 / KGP 2.4.20, compileSdk 37,
Build Tools 37.0.0, NDK 29.0.14206865, minSdk 29; temporary
`android.builtInKotlin=false` / `android.newDsl=false` retained unchanged.
No further toolchain migration was performed.

## CI contract

`.github/workflows/build-rdp.yml` runs on branch push and manual dispatch.
The existing main release/Firebase workflow is unchanged. Contents permission
is read-only; this workflow only uploads artifacts, without publishing releases.

- Temurin JDK 17, Flutter 3.50.0, SDK 37, Build Tools 37.0.0, CMake 4.1.2.
- NDK r29 downloaded directly from Google's `android-ndk-r29-linux.zip`;
  SHA256 checked before extraction, revision 29.0.14206865 checked afterward.
- Shallow clone FreeRDP tag 3.33.0 and require commit
  `5a10d7b6b79a2fbc62e8eba77085cd356dc303a6`.
- Upstream Studio `build.gradle`, `freeRDPCore/build.gradle`,
  `aFreeRDP/build.gradle`, settings and wrapper were read locally at that commit.
  Preserve upstream AGP 9.2.1 / wrapper Gradle 9.6.1. Write release.properties
  with the actual upstream property names, arm64 only, SDK/minSdk/CMake/NDK pins,
  and explicit version overrides to avoid shallow-history version-code inference.
  QA disables optional codecs and retains CJSON/OpenSSL, matching its build type.
- Run `:freeRDPCore:assembleQa`; copy `freeRDPCore-qa.aar` to
  `android/app/libs/freeRDPCore-qa.aar`. Inspect zip entries for arm64-only JNI
  libraries and the JNI entry library. Upload AAR before building the app so it
  remains available if APK compilation fails.
- Restore only wrapper jar/launchers and missing icons from Flutter 3.50 template;
  do not copy its wrapper properties. Assert the committed Gradle 9.5.0 URL.
- Build release APK with `--target-platform android-arm64 --dart-define=ACE_RDP=true`.
  Existing debug signing configuration remains; this is a prototype artifact.

Raw AAR + explicit runtime dependencies was selected to avoid adding a Maven
publishing build to upstream. `android/app/build.gradle` mirrors all upstream
runtime declarations exactly: appcompat 1.7.1, core 1.19.0, preference 1.2.1,
recyclerview 1.4.0, lifecycle viewmodel/livedata 2.11.0, Room runtime 2.8.4,
SQLCipher 4.17.0@aar, SQLite 2.7.0. Room compiler 2.8.4 executes upstream as an
annotation processor while creating the AAR; it is not an app runtime dependency.
Future upstream upgrades require reviewing this list again.

## App-local plugin boundary

`RdpPlugin.kt` registers a native PlatformView with a SurfaceView and waiting
label. A per-view MethodChannel `vn.aceremote.app/rdp/<id>` exposes `status`:
connection=false, H264 capability, native load error, current surface pixel size.
Only public `LibFreeRDP.hasH264Support()` is called; it triggers upstream native
loading. Linkage/runtime load failures display an error instead of escaping view
construction. No native instance is allocated, so no freeInstance call is needed.
No private JNI method, connection, authentication or native input is invoked.
`MainActivity` registers this app-local FlutterPlugin on its engine.

`RdpSurface` creates the AndroidView; non-Android uses a text fallback.
`RemotePage` enables it via ACE_RDP, and splits its available body exactly 50/50
using equal Expanded children. The existing laptopDeck/keyboardPanel code is
reused unchanged; AbsorbPointer prevents sending old HTTP input while waiting.
HTTP screenshot polling is disabled in RDP mode. Existing Home/auth/navigation
still use the HTTP agent; this step does not add independent RDP host navigation.

The surface is an unconnected rendering target, not remote graphics yet.
`status` reads actual Android view pixels; the next step must negotiate session
resolution from current top-half dimensions after layout and on resize/density
changes, with no hardcoded 1920x1080. Current code does not negotiate resolution.

## Verification and remaining scope

Before changes, Flutter 3.50.0 analyze exited 0 (no issues), full tests exited 0
(29/29). Post-change results are recorded in the status entry.
Workflow YAML parses and every run block passes `bash -n`; these are syntax
checks, not a GitHub Actions or Gradle execution. No Gradle/APK build ran on VM.

CI after push must establish actual tool/artifact availability, upstream native
external-dependency downloads/packaging, AAR compilation, app Kotlin/Gradle 9
compatibility, Maven dependency resolution, manifest/resource merge and minSdk
29 compatibility. Upstream includes extra activities, permissions and an
application theme; review the merged manifest in CI before device distribution.
Native load, waiting-surface rendering and no-crash behavior require Fold runtime
validation; neither Dart tests nor a successful APK build proves them.

Next: CI run and artifact inspection, then real session rendering/lifecycle,
viewport negotiation, JNI keyboard/pointer input and NLA authentication on Fold.
Planning estimate: 2–4 working days after CI packaging succeeds, conditional on
native lifecycle/authentication findings. No push was performed.

Final CLI `tokens used` is unavailable within the active turn. The supplied
interrupted step7 log has no final counter. Read the completed current CLI log
for the requested final total; do not substitute a live token_count snapshot.
