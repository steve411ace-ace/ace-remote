# Step 18 — launch crash: R8 removed FreeRDP JNI entry points

## Finding and confidence

A definite release-artifact defect explains startup failure: R8 removed/renamed
Java members that FreeRDP looks up by literal name from JNI during Application
startup. This is established from code plus the installed APK's matching bytes.
The phone's exact exception/signal has not been captured, and a successful fixed
release launch remains to be verified; no claim of device validation is made.

Only `android/app/proguard-rules.pro` changes runtime build behavior. No Kotlin,
Dart, manifest, upstream source, or workflow change; step 17 is untouched. Work
is on `rdp-prototype`, with no push, APK build, or Gradle execution on this VM.

## Concrete evidence

Upstream paths below are relative to
`~/workspace/FreeRDP-3.33.0/client/Android/Studio/freeRDPCore/src/main/`.
Flutter paths are relative to `~/workspace/flutter-3.50.0/`.

1. Ace's `android/app/src/main/AndroidManifest.xml:8` selects core `GlobalApp`.
   `java/com/freerdp/freerdpcore/application/GlobalApp.java:137–157` runs preferences,
   night mode, then `LibFreeRDP.setEventListener(this)` at line 147, without a
   catch. Calling this static method initializes LibFreeRDP before Flutter starts.
2. `java/com/freerdp/freerdpcore/services/LibFreeRDP.java:81–124` loads the native
   wrapper at line 85. That triggers `cpp/android_freerdp.c:1313–1353` JNI_OnLoad.
   Lines 1343–1344 look up `OnPointerSet` with signature `(J[IIIII)V`.
   Lines 1345–1350 look up `OnRailWindowUpdate` with `(JJII[I)V`; this second
   lookup is optional, but the first missing lookup's exception is not checked
   before subsequent JNI work. Thus failure can surface as a Java linkage error
   or an ART JNI abort, depending on execution and runtime checks.
3. `cpp/android_jni_callback.c:27–68` then looks up LibFreeRDP's no-argument
   constructor (`<init>`, `()V`, line 41) and instantiates it at line 49. A failed
   lookup leaves a pending exception; this constructor is also required.
4. Source has private static callbacks at `LibFreeRDP.java:766` and `:807` and
   an implicit public no-argument constructor. R8 cannot infer native string
   references from ordinary Java/Kotlin reachability.
5. Read-only DEX inspection of
   `/home/hatch/workspace/ace-remote/rdp-apk/ace-remote-rdp.apk` identified SHA256
   `d63268e29d0e090bc8e11f13093c65bdffc3645a2177bdaea54d1402f0032283`, matching
   the reported installed build. This was artifact identity plus a new DEX
   check, not a repeat of the excluded library/resource checks.
   `classes.dex` defines `Lcom/freerdp/freerdpcore/services/LibFreeRDP;` with
   `<clinit>`, static methods `a` through `q`, and native `freerdp_*` methods.
   Its encoded method definitions contain **no `<init>`, `OnPointerSet`, or
   `OnRailWindowUpdate`**. All direct and virtual definitions were inspected
   using Python stdlib zipfile/struct and DEX method/class tables.
6. Flutter's `packages/flutter_tools/gradle/src/main/kotlin/FlutterPlugin.kt:209–219`
   enables release minification and loads an existing app `proguard-rules.pro`.
   `FlutterPluginUtils.kt:233–239` defaults resource shrinking/minification on.
   Ace had no app ProGuard rules. Upstream `freeRDPCore/build.gradle:32–36`
   declares release build rules but no consumer keep rules. The app consumes a
   file AAR (`android/app/build.gradle`, dependencies block).

The supplied facts that native libraries and DT_NEEDED dependencies exist do
not protect Java callbacks from R8, validate JNI lookups, or prove dlopen/JNI_OnLoad
success. This finding is compatible with all supplied APK and CI facts.

## Startup suspects assessed and ranked

| Rank | Suspect | Evidence and disposition |
| --- | --- | --- |
| 1 | (a)/(b) LibFreeRDP initialization during GlobalApp.onCreate | Confirmed missing JNI members in the matching APK, as above. The call at GlobalApp.java:147 runs before any view/catch. Highest confidence causal defect. Other loader failures (symbol resolution, device linker/page-size constraints) are not excluded merely by DT_NEEDED presence, but have no additional evidence here. |
| 2 | (b) Preferences/night mode | GlobalApp.java:142–143 calls ApplicationSettingsActivity.get and getNightMode. ApplicationSettingsActivity.java:217–237 initializes the five XML defaults and client-name string; :330–345 reads the theme string and maps it to a valid night mode. Supplied APK facts exclude missing five XMLs/client-name strings, not corrupt preference types, reflective inflation failure, or every transitive resource. Client name appends a UUID before substring(0,31), so a short default name alone does not cause an index error. No concrete independent failing value found. |
| 3 | (c) Other engine/plugin startup failure | GlobalApp.java:40 extends plain android.app.Application and :139 calls super.onCreate. A FlutterApplication subclass is not required: local FlutterEngine.java:387–389 starts/completes loader initialization; :425–428 registers plugins, and FlutterFragmentActivity.java:746–764 supports generated registration. MainActivity.kt:6–9 extends FlutterFragmentActivity and calls super.configureFlutterEngine before adding RdpPlugin. No incompatible Application cast/init contract found. These facts reject the proposed inherent GlobalApp/FlutterApplication incompatibility; they do not guarantee every native/plugin initialization succeeds. |
| 4 | (b) Print monitor/receiver/manifest assumptions | GlobalApp.java:149–157 starts PrintJobMonitor then dynamically registers ScreenReceiver using ContextCompat.RECEIVER_EXPORTED. PrintJobMonitor.java:30–48 watches /sdcard/Download and invokes notification code only for matching CLOSE_WRITE events. ScreenReceiver.java:23–28 uses a valid GlobalApp cast and acts on screen broadcasts. No missing static receiver declaration is needed. No guaranteed launch exception found. Device filesystem/observer failures or an unrelated matching print-file event require logs. |
| 5 | (d) PlatformView construction | RdpPlugin.kt:27–28 only registers a factory. :53 creates RdpView when requested; :77–79 probes H264. LinkageError catches ExceptionInInitializerError, UnsatisfiedLinkError, and NoClassDefFoundError (all subclasses); RuntimeException is also caught. Unrelated Errors such as OutOfMemoryError and native signals are not caught, but have no supporting evidence. Crucially GlobalApp has already initialized LibFreeRDP before this probe. Catch widening or deferral would not repair its startup JNI failure. |
| 6 | (e) Dart first-frame RDP branch | main.dart:16–18 initializes bindings/runApp. :41 initializes ready/unlocked false; :257–259 shows a loading/PIN screen, then :318 Home. RemotePage is pushed by the Home button at :416–424. Only then does :1174–1179 build RdpConnectionPane. rdp_surface.dart:131–132 unconditionally builds RdpSurface behind the RDP form; :70–77 requests AndroidView before RDP Connect is tapped. Thus it is eager on RemotePage's first frame, **not the app's first frame**. RdpController starts with an idle map (:5–6) and only attaches after platform creation (:72–75). Dart initial loading errors are handled at main.dart:66–98. No first-frame Dart crash identified; existing widget tests exercise RDP form/controller behavior, not Android startup. |

Manifest comparison: the aFreeRDP sample's Application subclass is empty and adds
no initialization. Its HomeActivity/session request handler are navigation
components, not called by core GlobalApp.onCreate. Core library manifest declares
settings/session/print activities, ClipboardImageProvider and the keyboard service;
absence from Ace's *source* manifest does not imply absence after library manifest
merge. GlobalApp.get calls static settings helpers, not an Activity launch.
Settings XML references IntEditTextPreference by class name (constructor at
`utils/IntEditTextPreference.java:31–35`); its bounds initialization does not launch
an Activity. The XML's accessibility intent is opened only when selected.
PrintNotificationHelper.java:46–80 uses FileProvider and PrintProxyActivity only
on a print event. Ace declares the expected file-provider authority at manifest
lines 32–39, and its paths resource is supplied as verified. No additional sample
component was shown to be required for the ordinary launch path.

## Minimal fix

`android/app/proguard-rules.pro:4`:

```proguard
-keep class com.freerdp.freerdpcore.services.LibFreeRDP { *; }
```

Preserve this single JNI bridge class, its constructor, and all members with
original names. Keeping only native methods would miss the private Java callbacks
and constructor. Other callbacks are also resolved by name during sessions
(`android_jni_callback.c:114,148,184`), so retaining all bridge members is the
appropriate scope. R8 remains enabled for the rest of the app. The Flutter Gradle
plugin already includes this file; no build.gradle or workflow edit is necessary.
Agent-mode Dart behavior and branch main are unchanged.

## Validation on this VM

Requested commands were attempted using exactly SDK 3.50.0:

```sh
/home/hatch/workspace/flutter-3.50.0/bin/flutter analyze
/home/hatch/workspace/flutter-3.50.0/bin/flutter test
```

Both exited 1 **before analysis/tests ran**. Flutter's bootstrap script attempted
writes to the read-only SDK at `bin/cache/engine.stamp.tmp.*` and
`bin/cache/engine.realm` (update_engine_version.sh:71,78). This session permits
writes only in the app and /tmp. No SDK copy, modification, alternate SDK, Gradle,
or APK build was attempted. Previously supplied results remain 0 analyzer issues
and 35/35 passing tests; they are not fresh validation of this commit. Re-run the
two commands in an environment where this SDK's cache is writable. A Dart unit
test cannot exercise release shrinking/JNI; artifact and device checks below are
the necessary regression validation. `git diff --check` checks patch whitespace.

## CI and Fold6 acceptance after an explicitly authorized future build

No push or CI dispatch is performed here. Step 17 remains unchanged and unpushed.
The existing RDP CI builds the pinned upstream QA arm64 AAR, checks its native
library/ABI entries, then compiles/merges/shrinks the release APK with ACE_RDP=true.
It currently does **not** run flutter analyze/test, inspect post-R8 callbacks,
or launch on a device. Build success alone was insufficient before this fix.

Before considering the release validated, inspect the new APK's DEX to confirm
LibFreeRDP retains `<init>()V`, `OnPointerSet(J[IIIII)V`,
`OnRailWindowUpdate(JJII[I)V`, and the other private static On* callbacks under
their original names. With Android build-tools dexdump, for example:

```sh
unzip -p app-release.apk classes.dex > classes.dex
"$ANDROID_HOME/build-tools/37.0.0/dexdump" -d classes.dex > classes-dex.txt
```

Inspect the LibFreeRDP class's method definitions (repeat for other classes*.dex
if the class moves). The keep rule must be present in R8's effective configuration
and the mapping must preserve the bridge's names. These are acceptance checks,
not claims that this unchanged workflow automatically performs them.

On Fold6: install the newly identified release, force-stop/cold-launch repeatedly,
confirm the PIN/login screen appears, unlock and navigate to the RDP form without
pressing RDP Connect, then connect/disconnect/reconnect. Test folded/unfolded
orientation, keyboard/touch, framebuffer updates and pointer callbacks. Capture
startup logs to establish that the missing-method/JNI failure is gone and check
for a second independent failure. The literal native version 3.33.0 satisfies
LibFreeRDP's regex/version checks; absent H264 is supported (native probe returns
false when no context is available at android_freerdp.c:1273–1280).

## Exact Fold6 evidence if launch still fails

Run from a computer authorized for USB debugging. Do not clear app data/cache.
First save any existing crash evidence:

```sh
adb logcat -b crash -d -v threadtime > ace-rdp-existing-crash.txt
adb shell getprop ro.build.version.sdk > ace-rdp-device.txt
adb shell getconf PAGE_SIZE >> ace-rdp-device.txt
adb shell dumpsys package vn.aceremote.app > ace-rdp-package.txt
adb shell am force-stop vn.aceremote.app
adb logcat -b all -v threadtime > ace-rdp-launch-all.txt
```

Leave the last command running. In a second terminal reproduce the crash:

```sh
adb shell am start -W -n vn.aceremote.app/.MainActivity
adb logcat -b crash -d -v threadtime > ace-rdp-launch-crash.txt
adb shell dumpsys activity exit-info vn.aceremote.app > ace-rdp-exit-info.txt
adb bugreport ace-rdp-bugreport.zip
```

Stop the first terminal's logcat with Ctrl-C after capture. An optional focused
live view is `adb logcat -b all -v threadtime '*:E'`; keep the full files above
because filtering only by package/PID can lose linker, ART and crash_dump output.
If raw tombstones are accessible, use `adb shell ls -lt /data/tombstones` then
`adb pull /data/tombstones/tombstone_XX ace-rdp-tombstone.txt` with the matching
entry. Production Samsung devices normally deny direct access; use the bugreport's
tombstone/FS/data/tombstones content and SYSTEM_TOMBSTONE/dropbox sections instead.
No rooting is needed or requested. A Java exception may have no native tombstone.

Needed lines: complete AndroidRuntime FATAL EXCEPTION including every Caused by
and stack frame; LibFreeRDP/linker messages immediately before it; or ART's
`JNI DETECTED ERROR`, signal/abort message, native backtrace and build IDs for the
vn.aceremote.app PID. `NoSuchMethodError` mentioning OnPointerSet or `<init>`
(or a JNI abort with that pending exception) confirms this path on-device.
GlobalApp.onCreate frames identify which startup call failed; preference inflation,
ClassCastException, or resource errors would select suspect 2. `dlopen failed`,
missing-symbol or alignment diagnostics would select a distinct native loader
failure. Flutter engine/plugin frames versus RdpView constructor frames separate
suspects 3 and 5. Send the complete capture, not only the final fatal line.
