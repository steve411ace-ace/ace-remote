# Bước B1 — GlobalApp làm Application và FileProvider

Ngày: 2026-11-13 UTC. Repo Ace Remote: branch `rdp-prototype`, HEAD đầu vào
`32dc87e`; working tree sạch trước sửa. Đã đọc step11 và step12. An đã chọn
hướng 1: chấp nhận chạy GlobalApp nguyên trạng, kể cả ở agent-mode v1.4.
Chỉ đổi manifest, thêm XML paths và tài liệu này; chưa viết code kết nối.

## Nguồn đối chiếu

- `U/` = `/home/hatch/workspace/FreeRDP-3.33.0/client/Android/Studio/`.
- `J/` = `U/freeRDPCore/src/main/java/com/freerdp/freerdpcore/`.
- `F/` = `/home/hatch/workspace/flutter-3.50.0/`.

`git describe --tags --exact-match` tại source FreeRDP trả `3.33.0`.
Các kết luận Java/manifest dưới đây dựa trên source local, không phải kiểm chứng
bytecode AAR hoặc runtime APK.

## Application và Flutter embedding v2

`android/app/src/main/AndroidManifest.xml` đặt trực tiếp
`android:name="com.freerdp.freerdpcore.application.GlobalApp"`.
Giữ nguyên tất cả thuộc tính Application khác và các khai báo hiện có.
Android phải gọi lifecycle của GlobalApp: `sessionMap` là private static tại
`J/application/GlobalApp.java:43`, được gán trong `onCreate` tại dòng 145;
createSession/getSession dùng map này tại dòng 103–120. `onCreate` cũng đăng ký
GlobalApp làm LibFreeRDP.EventListener tại dòng 147.

Trong SDK 3.50.0, `F/packages/flutter_tools/gradle/src/main/kotlin/BaseApplicationNameHandler.kt:12–30`
đặt `defaultConfig.manifestPlaceholders["applicationName"]` mặc định thành
`android.app.Application`, hoặc giá trị project property `base-application-name`
nếu được truyền. FlutterPlugin gọi handler này tại dòng 188. Không thấy override
property/placeholder trong cấu hình Android của repo. Đây là đối chiếu source
cách resolve, chưa chạy Gradle để in giá trị merge thực tế.

`F/engine/src/flutter/shell/platform/android/io/flutter/app/FlutterApplication.java:9–18`
chỉ có class rỗng extends Application. MainActivity của Ace extends
FlutterFragmentActivity và đăng ký RdpPlugin trong configureFlutterEngine.
Delegate tạo engine qua FlutterEngineGroup (FlutterActivityAndFragmentDelegate.java:308–345),
FlutterEngine tự gọi startInitialization/ensureInitializationComplete (:387–390).
Theo source embedding v2, thay Application không bỏ mất logic khởi tạo Flutter
nào của FlutterApplication và không yêu cầu kế thừa class đó. Metadata
flutterEmbedding=2 vẫn giữ nguyên. Chưa kiểm chứng khởi động APK với GlobalApp.

## FileProvider và paths

Thêm provider đúng cấu hình `U/aFreeRDP/src/main/AndroidManifest.xml:97–105`:
androidx.core.content.FileProvider; authority cố định
`com.freerdp.afreerdp.fileprovider`; exported=false; grantUriPermissions=true;
metadata android.support.FILE_PROVIDER_PATHS trỏ @xml/file_provider_paths.
`J/presentation/PrintNotificationHelper.java:32,46–50` dùng chính authority này
để gọi FileProvider.getUriForFile, nên không đổi authority theo applicationId Ace.

`android/app/src/main/res/xml/file_provider_paths.xml` sao chép nguyên byte từ
file cùng tên của aFreeRDP: cache-path name=shared path="." và external-path
name=downloads path="Download/". Provider cho phép helper tạo content URI cho
file trong các đường dẫn này. `android/app/build.gradle` đã có dependency trực
tiếp `androidx.core:core:1.19.0`; không cần sửa dependencies.

## Tác dụng phụ đã được An chấp nhận

GlobalApp.onCreate (:137–158) không có điều kiện chọn RDP/agent-mode, vì vậy
những thao tác này cũng chạy khi dùng agent-mode v1.4:

- ApplicationSettingsActivity.get (:217–240) nạp defaults từ 5 XML:
  settings_app_client, settings_app_power, settings_app_security, settings_app_ui,
  settings_app_experimental. Nếu client name rỗng, tạo UUID ngẫu nhiên, ghép tên
  mặc định, cắt 31 ký tự và ghi SharedPreferences.
- Đặt AppCompat default night mode toàn tiến trình (GlobalApp:143;
  ApplicationSettingsActivity:330–345).
- Tạo và startWatching PrintJobMonitor (GlobalApp:149–150): theo dõi CLOSE_WRITE
  trong `/sdcard/Download`, lọc `rdp_print_*.pdf`, gọi PrintNotificationHelper
  (PrintJobMonitor:30–48). Khả năng đọc thư mục và thông báo thực tế chưa test.
- Đăng ký ScreenReceiver cho SCREEN_ON/OFF (GlobalApp:154–158).
  ScreenReceiver:25–34 gọi startDisconnectTimer khi tắt màn hình và cancel khi bật;
  GlobalApp:80–99 chỉ đặt timer khi disconnect timeout trong preferences > 0.

Đây là hành vi theo source được chấp nhận, chưa phải kết quả kiểm thử agent-mode
trên thiết bị. Không tách onCreate hoặc sửa Kotlin/Dart trong B1.

## Rà soát manifest core và rủi ro merge/resource

Đã đọc toàn bộ `U/freeRDPCore/src/main/AndroidManifest.xml`:

- Core không khai báo application android:name, nên không có tên Application
  thứ hai tại source này. Core thêm application theme=@style/Theme.Main và
  resizeableActivity=true cùng metadata Samsung keepalive.density.
- Các activity core: ShortcutsActivity (và alias CreateShortcuts), BookmarkActivity,
  ApplicationSettingsActivity, SessionActivity, AboutActivity, HelpActivity,
  PrintProxyActivity. Không trùng MainActivity Ace theo các manifest đã đọc.
  Một số activity exported=true và SessionActivity nhận URI scheme freerdp;
  các khai báo này sẽ cần được xem trong merged manifest trên CI.
- Provider core là .utils.ClipboardImageProvider, authority
  `com.freerdp.freerdpcore.clipboard`, khác tên/authority FileProvider mới.
  Service .presentation.KeyboardAccessibilityService không trùng service Ace
  (manifest main Ace không có service). Không thấy trùng tên/authority trong
  hai manifest source này; chưa kiểm tra merged manifest của toàn bộ dependencies.
- Ace không có @style/Theme.Main hay Theme.Main.Session. Core application và
  các activity tham chiếu chúng. Source core có định nghĩa tại
  res/values/theme.xml và res/values-night/theme.xml. Nếu AAR thật thiếu các
  resource đó, resource link sẽ lỗi; không kết luận merge/build sẽ pass.
- KeyboardAccessibilityService tham chiếu @xml/keyboard_accessibility_service
  và @string/accessibility_keyboard_label. Ace không có XML này; source core có
  res/xml/keyboard_accessibility_service.xml. Cần xác nhận AAR thực sự đóng gói
  XML và các resource phụ thuộc, cũng như các string/theme khác trong manifest.
- Core còn bổ sung permissions network/storage/audio/camera/notifications và
  supports-screens. Chưa đánh giá hành vi runtime hay permission trên thiết bị.

`android/app/libs/freeRDPCore-qa.aar` không có trên VM; git check-ignore xác nhận
đường dẫn này bị ignore. Không có manifest merge thật trong B1. Chỉ CI có AAR
thật mới kiểm chứng được manifest merge (kể cả dependencies bắc cầu), Kotlin
compile với API AAR thật và Android resource link. Không chạy Gradle/build APK,
không kích hoạt CI và không khẳng định merge sẽ pass.

## Kiểm chứng VM và blocker

Chỉ gọi `/home/hatch/workspace/flutter-3.50.0/bin/flutter`, không dùng SDK cũ.
Lần chạy đầu trong sandbox Codex (workspace-write) cả ba lệnh đều exit 1 do SDK
cache read-only (bin/internal/update_engine_version.sh:71,78 không ghi được
bin/cache/engine.stamp.tmp.* và bin/cache/engine.realm). Chạy lại ngoài sandbox
với quyền ghi cache SDK thì cả ba đều pass:

| Lệnh | Kết quả thực tế |
|---|---|
| flutter pub get | Exit 0, Got dependencies. |
| flutter analyze | Exit 0, No issues found (7.2s). |
| flutter test | Exit 0, 30 pass, 0 fail, "All tests passed!". |

Test có warning tap miss trong widget tests hiện có; không có test fail. Kết quả
này là kiểm chứng Dart; AAR không có trên VM nên vẫn chưa kiểm chứng Kotlin
compile, manifest merge hay resource link — chỉ CI mới làm được.

Kiểm tra XML bằng parser, đối chiếu provider với mẫu, so sánh paths nguyên byte
và kiểm tra giữ nguyên cấu trúc manifest cũ ngoài thay Application/thêm provider:
đều pass. `git diff --check` pass. Các kiểm tra tĩnh này không thay thế Flutter,
manifest merger, Kotlin compiler, resource linker hoặc kiểm thử APK trên thiết bị.
Không push, không đụng PC của An, không dùng credentials.

Commit cũng bị chặn trong sandbox Codex: đã thử git add đúng ba file và git
commit, nhưng git add exit 128 vì không tạo được `.git/index.lock` (Read-only
file system trong sandbox). Commit được tạo ngoài sandbox sau khi kiểm chứng
Flutter pass; xem git log. Không thay đổi quyền/mount Git để vượt giới hạn
phiên. Không push, không đụng PC của An, không dùng credentials.
