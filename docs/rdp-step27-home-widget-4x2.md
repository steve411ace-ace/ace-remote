# Bước 27 — Widget màn hình chính Android 4x2

Ngày 14/11/2026. An yêu cầu (06:41): widget 4x2, sáng/tối theo app, cài đặt
độ trong suốt 0–100% trong Cài đặt, trên widget có thông tin kết nối + chỉnh
nhanh trackpad/bàn phím + phím chuyển đổi kết nối + chạm vào widget thì kết
nối thẳng tới kết nối đó.

## Cách làm đã chọn

### Package: `home_widget` 0.10.0 (pub.dev, mới nhất lúc làm)

- Thêm bằng `flutter pub add home_widget` → `pubspec.yaml` có
  `home_widget: ^0.10.0`. Yêu cầu Dart `>=3.10.0`, Flutter `>=3.38.1` —
  thỏa với Flutter 3.50.0 / Dart 3.14.0 của repo.
- Chỉ dùng 3 API của package: `HomeWidget.saveWidgetData` (ghi dữ liệu),
  `HomeWidget.updateWidget` (báo Android vẽ lại) và
  `HomeWidget.initiallyLaunchedFromHomeWidget` / `HomeWidget.widgetClicked`
  (nhận deep link khi mở app từ widget).
- **KHÔNG dùng `registerInteractivityCallback` / background callback.**
  Đã đọc source 0.10.0 (`HomeWidgetBackgroundWorker`,
  `HomeWidgetBackgroundService`): isolate nền tạo `FlutterEngine(context)`
  trần, KHÔNG gọi `GeneratedPluginRegistrant` — chỉ đăng ký channel
  `'home_widget/background'`. Trong isolate đó, `saveWidgetData` /
  `updateWidget` (channel `'home_widget'`) và `SharedPreferences` đều ném
  `MissingPluginException`. Nên **mọi nút trên widget đều dùng launch
  intent**: bấm → mở app → app thực hiện hành động → app sync lại widget.
  Chậm hơn toggle nền một nhịp mở app, nhưng chắc chắn chạy được.

### Widget native: XML RemoteViews, KHÔNG dùng Jetpack Glance

- Tài liệu home_widget mặc định dùng Glance, nhưng Glance cần thêm
  `androidx.glance:glance-appwidget` + `buildFeatures { compose true }`
  vào `android/app/build.gradle` — file này TUYỆT ĐỐI KHÔNG được đụng ở
  bước này (chứa config fixed key bước 20). XML chỉ cần manifest +
  `res/xml` + `res/layout` + provider Kotlin, không đụng build.gradle.
  Plugin tự khai Glance trong build.gradle của chính nó nên XML vẫn
  compile được.
- Provider: `AceRemoteWidgetProvider : HomeWidgetProvider()` — override
  `onUpdate(context, appWidgetManager, appWidgetIds, widgetData)` (4 tham
  số, đọc `SharedPreferences` file `HomeWidgetPreferences` do plugin ghi).
- Kích thước 4x2: `android:minWidth="250dp"`, `android:minHeight="110dp"`,
  `android:targetCellWidth="4"`, `android:targetCellHeight="2"`,
  `updatePeriodMillis="0"` (app tự đẩy update, widget không tự poll),
  `resizeMode="horizontal|vertical"`.

### Nền bo góc + độ trong suốt (cái khó nhất của bước này)

RemoteViews không cho set đồng thời màu nền và alpha của một shape, và
`setBackgroundColor` sẽ làm mất góc bo. Cách làm: provider tự vẽ một
bitmap hình chữ nhật bo góc (400×200, bo 48px ≈ 20dp) với màu nền +
alpha từ opacity rồi gán vào `ImageView` nền (`setImageViewBitmap`).
Chỉ nền mang opacity — chữ và nút luôn đục 100%.

### Deep link

Scheme riêng `aceremote`, đăng ký intent-filter
`es.antonborri.home_widget.action.LAUNCH` trên MainActivity:

| URI | Hành động |
|---|---|
| `aceremote://connect/<id>` | Mở app, kết nối thẳng tới kết nối `<id>` |
| `aceremote://toggle-trackpad` | Bật/tắt Trackpad của kết nối hiện tại |
| `aceremote://toggle-keyboard` | Bật/tắt hiện bàn phím của kết nối hiện tại |
| `aceremote://next-connection` | Chuyển sang kết nối đã lưu tiếp theo |
| `aceremote://open` | Chỉ mở app (khi chưa có kết nối nào lưu) |

App xử lý cả 2 đường: khởi động lạnh (`initiallyLaunchedFromHomeWidget`
trong `load()`) và đang chạy (`HomeWidget.widgetClicked` stream trong
`initState()`; URI tới trước khi app ready thì xếp hàng `_pendingWidgetUri`
rồi xử lý sau). URI lạ (scheme/host khác) bị bỏ qua.

### Luồng dữ liệu (đồng bộ 2 chiều)

Chung một chỗ lưu, không đổi cấu trúc bước 23:

- Kết nối: prefs `rdp_connections` + secure storage `rdp_username_<id>` /
  `rdp_password_<id>` (bước 23, giữ nguyên).
- Theme: prefs `ace_remote_v1_theme` (bước 24).
- Mới: prefs `ace_widget_opacity` (0–100, mặc định 100) và
  `ace_widget_current_id` (kết nối widget đang hiện).
- `HomeWidgetSync` (`lib/home_widget_data.dart`) ghi dữ liệu hiển thị vào
  file `HomeWidgetPreferences` rồi gọi `updateWidget`: `widget_name`,
  `widget_address`, `widget_status`, `widget_trackpad`, `widget_keyboard`,
  `widget_has_next`, `widget_dark`, `widget_opacity`,
  `widget_connection_id`. Sync là best-effort (không throw) — plugin lỗi
  thì app vẫn chạy, widget chỉ không cập nhật.
- "Kết nối hiện tại" của widget = id đã lưu trong `ace_widget_current_id`;
  nếu id đó bị xóa/mất thì tự sửa về favorite, rồi kết nối đầu tiên.
  Mở một kết nối từ Home hay từ widget đều ghi id đó xuống.
- App sync widget sau mỗi thay đổi: đổi theme/opacity (trong `save()`),
  mở kết nối (trong `Home._open`), thêm/sửa/xóa/yêu thích kết nối (trong
  `Home._reload`), và sau mỗi hành động từ widget.
- Theme hiệu lực của widget: Sáng/Tối theo app; "Theo điện thoại" thì theo
  độ sáng hệ thống (`PlatformDispatcher.platformBrightness`) — cùng luật
  với app (bước 24).
- Chống mở trùng phiên RDP: `_AceAppState.openConnectionId` theo dõi
  RemotePage đang mở (Home và widget cùng ghi); bấm widget "Kết nối" cho
  đúng kết nối đang mở thì không làm gì (mở thêm một RemotePage sẽ thử
  phiên RDP thứ hai trong khi phiên đầu còn chạy).

### Giao diện widget

- Hàng trên: tên kết nối (đậm), `host:port`, dòng trạng thái
  `Đã lưu • Trackpad/Chạm` (+ `• Ẩn bàn phím` nếu tắt bàn phím). Chạm vào
  hàng này = kết nối.
- Hàng dưới: 3 nút — Trackpad, Bàn phím, Kết nối. Nút đang bật có nền
  xanh ngọc `#2BB3A3` (cùng màu phím active của app); nút tắt nền xám
  (`#3A4542` tối / `#E8E8E8` sáng).
- Nút chuyển đổi `⇄` ở góc phải hàng trên, chỉ hiện khi có > 1 kết nối.
- Chưa có kết nối nào: tên `Chưa có kết nối`, 2 nút toggle ẩn, nút
  `Kết nối` thành `Mở app`.
- Màu nền/chữ theo theme: tối nền `#1E2E2C` chữ trắng, sáng nền trắng chữ
  `#333333`, chữ phụ `#B0BEC5` / `#666666`.

### Màn hình Cài đặt (app)

Thêm mục "Widget màn hình chính": slider độ trong suốt 0–100% (lưu khi
thả tay — không sync widget theo từng tick lúc kéo) + ghi chú
"0% là trong suốt hoàn toàn, 100% là đục hoàn toàn. Widget theo chế độ
Sáng/Tối ở trên." + nút "Thêm widget ra màn hình chính" (chỉ hiện khi
`HomeWidget.isRequestPinWidgetSupported()` = true, Android 8+; bấm thì
hệ thống hỏi ghim widget).

## File đổi

| File | Nội dung |
|---|---|
| `pubspec.yaml`, `pubspec.lock` | Thêm `home_widget: ^0.10.0` |
| `lib/home_widget_data.dart` (mới) | Model + sync + deep link + helper thuần (clamp/alpha/theme/next) |
| `lib/main.dart` | `_AceAppState`: nhận deep link, `_openRemote`, `_settingsPage`, lưu opacity + sync; `Home`: param `openConnectionId`, `_open`/`_reload` sync widget; `SettingsPage`: slider opacity + nút ghim widget; fallback SettingsPage trong menu RemotePage thêm param mới |
| `android/app/src/main/AndroidManifest.xml` | Intent-filter LAUNCH cho MainActivity + receiver `AceRemoteWidgetProvider` |
| `android/app/src/main/kotlin/vn/aceremote/app/AceRemoteWidgetProvider.kt` (mới) | Provider: đọc widget data, vẽ nền bo góc + alpha, gán launch intent cho từng nút |
| `android/app/src/main/res/xml/ace_remote_widget_info.xml` (mới) | Info 4x2 |
| `android/app/src/main/res/layout/ace_remote_widget.xml` (mới) | Layout RemoteViews |
| `android/app/src/main/res/drawable/widget_pill_on.xml`, `widget_pill_off_light.xml`, `widget_pill_off_dark.xml` (mới) | Nền bo góc cho nút bật/tắt |
| `test/home_widget_data_test.dart` (mới, 21 test) | Deep link, opacity, theme, next-connection, model, sync (mock channel `home_widget`) |
| `test/settings_test.dart` | 3 chỗ dựng SettingsPage thêm param mới + 2 test slider (hiện giá trị, kéo rồi lưu khi thả) |

Không đụng: `android/app/build.gradle`, 2 workflow, `proguard-rules.pro`,
PIN, logic Caps Lock bước 22, cấu trúc lưu trữ bước 23.

## Kiểm chứng

- `flutter analyze`: **0 issue**.
- `flutter test`: **95/95 pass** (72 cũ + 21 test widget mới + 2 test
  slider mới).
- Token Codex: **0** (làm trực tiếp).

## Cách test trên Fold6 (cần máy thật — VM không test được widget native)

1. Cài bản run #15 (vẫn ký debug key → gỡ bản cũ rồi cài), mở app.
2. Thêm widget: giữ lâu màn hình chính → Widgets → Ace Remote → kéo ra
   (4×2). Widget hiện tên/host/status của kết nối hiện tại.
3. Chạm vùng thông tin hoặc nút "Kết nối" → app mở và nối thẳng RDP
   tới kết nối đó.
4. Bấm nút Trackpad → app mở + SnackBar "Đã bật/tắt Trackpad cho …";
   nút trên widget đổi màu; mở Edit của kết nối đó kiểm tra công tắc
   Trackpad đã đổi theo. Bấm "Bàn phím" tương tự.
5. Thêm kết nối thứ 2 (Home → +) → nút `⇄` hiện trên widget; bấm `⇄` →
   SnackBar "Đã chuyển sang …", widget đổi sang tên kết nối tiếp theo.
6. Cài đặt → đổi Sáng/Tối → widget đổi nền/chữ theo; chọn "Theo điện
   thoại" → đổi theme hệ thống → widget theo.
7. Cài đặt → kéo slider độ trong suốt: 0% nền widget biến mất (chỉ còn
   chữ/nút), 100% đục hoàn toàn; 50% mờ một nửa.
8. Cài đặt → nút "Thêm widget ra màn hình chính" (nếu hiện) → hệ thống
   hỏi ghim widget.
9. Xóa hết kết nối → widget hiện "Chưa có kết nối", nút "Mở app".

## Giới hạn chưa kiểm chứng (cần máy thật)

- Provider/layout native chỉ compile trên CI, chưa từng chạy: cần test
  tay 9 bước trên. Nếu widget không hiện trong danh sách Widgets của
  launcher, hoặc bấm nút không mở app, lấy logcat (`adb logcat | grep -i
  widget`) để xem provider có được gọi không.
- Toggle từ widget chỉ đổi config đã lưu, KHÔNG đổi phiên RDP đang chạy
  (muốn đổi phiên đang chạy: ngắt rồi nối lại — lúc nối, pane áp dụng
  config mới).
- Trạng thái trên widget là "Đã lưu" (widget không biết phiên RDP có đang
  chạy không) — không hiện "Đang kết nối".
- Ký tự `⇄` trên nút chuyển đổi: nếu font máy không có sẽ hiện ô vuông —
  báo lại để đổi sang chữ "Tiếp".
- Nút ghim widget cần Android 8+ và launcher hỗ trợ; nếu không thấy nút
  thì thêm widget thủ công như bước 2.
- Nền bitmap bo góc 48px trên bitmap 400×200, co giãn theo kích thước
  widget thật — trên mật độ màn hình khác có thể hơi lệch 20dp chuẩn,
  không đáng kể.
