# Bước 10 — sửa compileSdk của local_auth_android (CI run #3)

## Nguyên nhân và bằng chứng

Log CI do người giao việc cung cấp (không truy cập Actions trong phiên này):

```text
:local_auth_android:checkReleaseAarMetadata
:flutter_plugin_android_lifecycle requires consumer compileSdk >= 35
:local_auth_android is currently compiled against android-34
```

Đã đọc lại source thực tế trong `~/.pub-cache/hosted/pub.dev/`:

- Lock cũ: `local_auth 2.3.0`, `local_auth_android 1.0.47`,
  `flutter_plugin_android_lifecycle 2.0.26`.
- `local_auth_android-1.0.47/android/build.gradle`: hard-code `compileSdk 34`,
  AGP 8.5.0, core 1.13.1, biometric 1.1.0.
- `flutter_plugin_android_lifecycle-2.0.26/android/build.gradle`: compileSdk 35.
  Đây là dependency pub transitive của plugin, không phải package của SDK.
  Yêu cầu consumer >=35 được xác định từ log CI; chưa đọc metadata AAR.
- CompileSdk 37 của app không thay compileSdk riêng của plugin.
- `lib/main.dart` dùng thật LocalAuthentication và AndroidAuthMessages khi
  biometric + có PIN, nên không gỡ package.

## Hướng sửa duy nhất: nâng nhóm local_auth (a)

Đã gọi API pub.dev trực tiếp, resolve bằng Flutter 3.50.0 và đọc source archive
được pub tải vào cache, không sửa cache hay lock bằng tay.

`local_auth_android-2.3.0/android/build.gradle.kts` đặt:

```kotlin
compileSdk = flutter.compileSdkVersion
```

`~/workspace/flutter-3.50.0/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt:23`
đặt `compileSdkVersion = 36`. Vì vậy plugin mới dùng 36 (>=35), không phải 37.
Gradle plugin mới khai AGP 8.13.1, Kotlin 2.3.20, Java/JVM 17, minSdk 24,
core 1.18.0, biometric 1.1.0, fragment 1.8.9. App minSdk 29 đáp ứng.
Changelog Android 2.0.9 ghi chuyển sang built-in Kotlin để hỗ trợ AGP 9.

Pubspec cache xác nhận:

- local_auth 3.0.2 yêu cầu Dart ^3.10.0, Flutter >=3.38.0.
- local_auth_android 2.3.0 yêu cầu Dart ^3.12.0, Flutter >=3.44.0.
- Flutter VM thực tế: 3.50.0, Dart 3.14.0; đáp ứng các minimum và constraint
  app ^3.5.4. Pub resolve thành công với toàn bộ dependency hiện tại.

Chọn nâng package vì sửa trực tiếp nguồn compileSdk 34 và có hỗ trợ AGP 9
trong upstream; không cần ép subprojects hoặc sửa Gradle/workflow.
Chỉ đổi đúng 5 package trong lock:

| Package | Cũ | Mới | Lý do |
| --- | --- | --- | --- |
| local_auth | 2.3.0 | 3.0.2 | Nâng API chính sang dòng hỗ trợ Android 2.x |
| local_auth_android | 1.0.47 | 2.3.0 | Bỏ hard-code compileSdk 34, hỗ trợ built-in Kotlin |
| local_auth_darwin | 1.4.3 | 2.0.5 | local_auth mới yêu cầu ^2.0.0 |
| local_auth_platform_interface | 1.0.10 | 1.1.0 | local_auth mới yêu cầu ^1.1.0 |
| local_auth_windows | 1.0.11 | 2.0.2 | local_auth mới yêu cầu ^2.0.0 |

Lifecycle giữ nguyên 2.0.26; không upgrade dependency ngoài nhóm này.

## File sửa và API migration

- `pubspec.yaml`: local_auth ^3.0.2, local_auth_android ^2.3.0.
- `pubspec.lock`: pub get cập nhật 5 package trên và checksum tương ứng.
- `lib/main.dart`: đổi biometricHint thành signInHint; bỏ các named parameter
  AndroidAuthMessages đã bị upstream xóa; giữ cancelButton, signInTitle.
  Thay AuthenticationOptions bằng tham số biometricOnly: true.
  Nhận thêm LocalAuthException trong nhánh thông báo dùng PIN có sẵn vì
  upstream đổi loại exception từ PlatformException.
- Sửa chính tài liệu này, bỏ blocker sandbox cũ đã hết.

API 3.x bỏ native error/settings dialog của useErrorDialogs; các chuỗi tùy chỉnh
cho dialog đó không còn được hỗ trợ. App dùng nhánh báo lỗi/PIN có sẵn,
không bổ sung flow tính năng. Cần kiểm tra biometric trên thiết bị thật sau CI.

## Kiểm chứng VM

Mọi lệnh Flutter dùng đúng `~/workspace/flutter-3.50.0/bin/flutter`.
Không chạy Gradle, không build APK trên VM.

- `flutter pub get`: exit 0, Got dependencies/Changed 5 dependencies.
- `flutter analyze` sau sửa API và exception: exit 0, No issues found (0 issue).
- `flutter test --reporter expanded`: 30 pass, 0 fail; có warning tap không trúng
  widget ở remote_test.dart, không làm test fail. Chạy lại sau chỉnh exception.
- `git diff --check`: thành công.
- Đã đọc lại cả android/build.gradle và android/app/build.gradle sau sửa;
  hai file không có diff. Giữ compileSdk app 37, core 1.19.0,
  project.buildDir/evaluationDependsOn và toàn bộ cấu hình FreeRDP/NDK/CMake/AAR.
  Không đổi workflow, RdpPlugin hoặc RemotePage. Không có blocker SDK/pub.

## CI cần kiểm chứng và rủi ro còn lại

Chỉ CI sau khi Muse review rồi commit/push mới kiểm chứng build APK release
bằng AGP 9.3.1 / Gradle 9.5.0 với AAR FreeRDP 3.33.0 arm64 thật.
Source plugin mới và resolve Dart chứng minh đã bỏ compileSdk 34;
chưa chứng minh APK build thành công. Có thể còn lỗi tích hợp Gradle/Kotlin,
Java 17, Android dependency/AAR metadata khác mà analyze/test Dart không thấy.
Cần kiểm tra luồng biometric/PIN trên Android thật, nhất là lỗi chưa enroll hoặc
lockout vì API mới bỏ native error/settings dialog.

Đã commit lên branch `rdp-prototype` (Muse kiểm chứng độc lập, commit sau khi review diff); chưa push — Muse sẽ push từ PC rồi theo dõi CI chạy lại.
