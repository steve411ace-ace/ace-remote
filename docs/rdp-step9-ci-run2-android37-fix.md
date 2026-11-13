# RDP step 9: CI run #2 — Android SDK package name

Investigation date: 2026-11-13. Branch: `rdp-prototype`; starting HEAD:
`9b9f4f5f2257125bda47906821fc1c8d59125072`.

## Failure

Run #2 (43436774072, commit fedee01), as supplied in the task: setup-android
passed in 1m04s after the obsolete `tools` package was removed. The next step
failed after 1s with `Warning: Failed to find package 'platforms;android-37'`
and exit 1. FreeRDP AAR/APK builds were skipped; no artifacts. This investigation
did not independently retrieve the GitHub run log (this checkout has no remote).

## Repository evidence

Downloaded the following official XMLs with Python urllib/curl, parsed with
`xml.etree.ElementTree`, and compared exact `remotePackage/@path` values:

| Repository URL | SHA-256 of downloaded bytes | API 37 entries |
| --- | --- | --- |
| https://dl.google.com/android/repository/repository2-1.xml | `77fe1efa0850bc46a87a14e66dab802041277f2014a139a5c9df44608fd12b92` | None |
| https://dl.google.com/android/repository/repository2-2.xml | `a83140b85d34d42706643aa273be4a5ad3413fba002e2dab2ff2fca02031c857` | None |
| https://dl.google.com/android/repository/repository2-3.xml | `d670de8bce15cc4ecf5d1a135f2168137ccbb8402111dfc8efcf9cb6f3b2f28f` | 37.0, 37.1, 37.2, 37.2-beta1/2/3 |
| https://dl.google.com/android/repository/repository2-4.xml | `f56188380e3e53349970386fbb38a2ffdfc526b31f9b82e8083e04f8180939bf` | Same package paths as schema 3 |

**`platforms;android-37` exists in none of these XMLs.** These are schema
versions, not separate release channels. Each XML declares channel-0 stable,
channel-1 beta, channel-2 dev, channel-3 canary.

Relevant schema 3/4 entry (abridged):

```xml
<remotePackage path="platforms;android-37.0">
  <type-details xsi:type="sdk:platformDetailsType">
    <api-level>37.0</api-level>
    <codename/>
    <extension-level>22</extension-level>
    <base-extension>true</base-extension>
  </type-details>
  <revision><major>2</major></revision>
  <display-name>Android SDK Platform 37.0</display-name>
  <uses-license ref="android-sdk-license"/>
  <channelRef ref="channel-0"/>
  <!-- archive: platform-37.0_r02.zip, size 67281901,
       SHA-1 ed8ebf7f8822a4de5686d427f237d2fa30ff7410 -->
</remotePackage>
```

`build-tools;37.0.0` revision 37.0.0 and `cmake;4.1.2` revision 4.1.2 also
exist on channel-0 (including in schema 1). No preview channel is needed.
The beta-suffixed platform entries also carry channel-0 in these XMLs; channel
alone must not be used to infer whether a package is a preview.

Downloaded [platform-37.0_r02.zip](https://dl.google.com/android/repository/platform-37.0_r02.zip),
and verified its SHA-1 against the XML. Its `android-37.0/source.properties`:

```properties
Platform.Version=17
Pkg.Revision=2
AndroidVersion.ApiLevel=37.0
AndroidVersion.CodeName=
AndroidVersion.ExtensionLevel=22
AndroidVersion.IsBaseSdk=true
AndroidVersion.PreviewSdkInt=0
AndroidVersion.BetaVersion=
```

Its `build.prop` further reports `ro.build.version.sdk=37`,
`ro.build.version.sdk_full=37.0`, `ro.build.version.codename=REL`, and
`ro.build.version.preview_sdk=0`. This proves the selected Android 17 SDK is
released/stable, not a preview or an unpublished API.
[Android's setup page](https://developer.android.com/about/versions/17/setup-sdk)
documents `compileSdk = 37` (although its GUI instructions still say Preview);
the archive metadata above resolves that ambiguity for the selected package.

## setup-android and reproduction

[v3/action.yml](https://github.com/android-actions/setup-android/blob/v3/action.yml)
defaults `cmdline-tools-version` to `12266719`.
[v3/src/main.ts](https://github.com/android-actions/setup-android/blob/v3/src/main.ts)
maps that build to 16.0, reuses a matching preinstalled tool or downloads
`commandlinetools-linux-12266719_latest.zip`, then adds its bin directory to PATH.
This establishes what the workflow requests; the historical runner's exact
installation was not independently inspected.

Downloaded that official archive on this VM; `source.properties` confirms
`Pkg.Revision=16.0`. Its sdklib JAR includes repository schema 3 and a string
`api-level` field supporting minor versions. No tool update is necessary.

Live Java sdkmanager repository downloads failed on this VM: direct requests
reported IO exceptions; explicit VM HTTP proxy requests reported
`java.net.SocketException: Connection reset`. A separate exploratory tools 23.0
attempt also failed to connect to the remote repository; it is not used by the fix.
Therefore this is not a claim that live sdkmanager downloads passed on this VM.

To isolate parsing/package resolution from that network limitation, served the
unmodified downloaded XMLs through sdklib's `SDK_TEST_BASE_URL=file:///.../`
test override. With tools 16.0 and JDK 17:

```sh
SDK_TEST_BASE_URL=file:///tmp/ace-sdk-investigation/ \
JAVA_HOME=/home/hatch/workspace/jdk17 \
/home/hatch/workspace/ace-sdk-investigation/12266719/cmdline-tools/bin/sdkmanager \
  --sdk_root=/home/hatch/workspace/ace-sdk-investigation/sdk16file \
  --list --channel=0
```

Actual relevant output (exit 0):

```text
build-tools;37.0.0     | 37.0.0 | Android SDK Build-Tools 37
cmake;4.1.2            | 4.1.2  | CMake 4.1.2
platforms;android-37.0 | 2      | Android SDK Platform 37.0
```

There was a warning about unavailable addon source lists (not mirrored); the
platform repository parsed successfully. Also placed the verified platform ZIP
beside the local XMLs and installed `platforms;android-37.0 --channel=0` using
the same tools and a separate SDK root (accepted the SDK license). Exit 0;
`sdkmanager --list_installed` confirms:

```text
platforms;android-37.0 | 2 | Android SDK Platform 37.0 | platforms/android-37.0
```

This validates tools 16.0 parsing and installation with the published package
name. Downloaded tools/SDK/logs remain outside git. No repository update, cache
purge, preview channel, or dependency downgrade is justified by the evidence.

Using the same local repository and tools, requesting the old exact name
`platforms;android-37 --channel=0` reproduced
`Warning: Failed to find package 'platforms;android-37'` with exit 1.

## Selected fix and impact

One direction: correct the SDK package name in `.github/workflows/build-rdp.yml`
to `platforms;android-37.0`. Explicit `--channel=0` documents stable selection;
pin `cmdline-tools-version: '12266719'` to the tested current v3 default.
Keep the obsolete-tools fix (`packages: platform-tools`).

No app configuration or source changes. App compileSdk remains 37 and minSdk
remains 29; targetSdk still comes from Flutter. FreeRDP release.properties
remains COMPILE_API=37, TARGET_API=37, MIN_API=29; Build Tools remains 37.0.0.
AndroidX core remains 1.19.0: its minCompileSdk=37 requirement supplied in the
task is preserved, not bypassed. The upstream checked-out freeRDPCore/build.gradle
line 70 independently confirms the 1.19.0 dependency. No native compatibility
claim for a downgraded AndroidX is needed because no dependency changes.

## Validation and remaining CI work

- Python PyYAML `safe_load`: PASS.
- `bash -n` on all 6 workflow `run` blocks: PASS.
- `git diff --check`: PASS.
- Flutter analyze/test: not run; only workflow/docs changed, no app code/config.
- No Gradle or APK build run on the VM; no Flutter SDK copied to /tmp.
- No push. Only workflow and this document are committed on `rdp-prototype`.

CI rerun must verify live Google repository access and installation, NDK
download/checksum, FreeRDP AAR native build, AGP SDK resolution for compileSdk 37,
Flutter APK build, and both artifact uploads. Local SDK installation alone does
not prove those later stages pass. Native/toolchain/runtime issues beyond the
original SDK package lookup remain unverified until CI/device testing.
