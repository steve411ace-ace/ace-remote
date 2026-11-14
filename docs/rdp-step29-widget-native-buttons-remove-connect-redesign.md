# Bước 29 — Widget: nút native không mở app, bỏ nút "Kết nối", làm đẹp widget

Phản hồi của An khi test bản run #15 (widget 4x2 trên màn hình chính Fold6):

1. "Nút chuyển là tự chuyển trên widget luôn."
2. "bấm vào widget đã kết nối rồi nên không cần nút kết nối nữa."
3. "xấu quá toàn bộ widget đều xấu, icon xấu. Làm đẹp hơn, hiện đại hơn đi em."
4. Bổ sung (07:18): "Thêm nữa các nút bấm vào đổi trạng thái, config là oke
   đúng tính năng rồi. Bấm vào các nút em mở app lên chi vậy." — **tất cả**
   các nút trên widget đều phải đổi trạng thái/config NGAY TRÊN WIDGET,
   không mở app. Chỉ chạm vào vùng thông tin kết nối mới mở app và kết nối
   thẳng tới kết nối đó.

## 1. Nút native: Trackpad / Bàn phím / chuyển đổi đều đổi ngay trên widget

### Cách làm

`AceRemoteWidgetProvider` xử lý click HOÀN TOÀN TRONG KOTLIN, không qua
Flutter engine, không mở app:

- Mỗi nút gắn một `PendingIntent.getBroadcast` với action riêng, explicit tới
  chính provider:
  - `vn.aceremote.app.widget.ACTION_TOGGLE_TRACKPAD` (requestCode 101)
  - `vn.aceremote.app.widget.ACTION_TOGGLE_KEYBOARD` (requestCode 102)
  - `vn.aceremote.app.widget.ACTION_NEXT_CONNECTION` (requestCode 103)
- `onReceive` chặn 3 action này, gọi `handleNativeAction()` rồi `return`
  (không gọi `super.onReceive`, app không bao giờ được mở). Mọi broadcast
  khác (APPWIDGET_UPDATE, APPWIDGET_ENABLED, …) vẫn rơi về
  `HomeWidgetProvider` như cũ. Không cần thêm intent-filter trong manifest
  (PendingIntent explicit đã chỉ rõ component) nên `AndroidManifest.xml`
  không đổi.
- `handleNativeAction` đọc danh sách kết nối từ SharedPreferences, áp dụng
  thay đổi, ghi lại, rồi `refreshAllWidgets()` vẽ lại mọi instance widget
  ngay lập tức. Mọi lỗi đều được `try/catch` trong `onReceive` — một lần
  bấm lỗi không bao giờ crash receiver hay mở app; widget chỉ giữ nguyên
  trạng thái cũ.
- Sau khi đổi, provider ghi lại cả `HomeWidgetPreferences` (file hiển thị
  mà `bind()` đọc) qua `mirrorDisplayState()` — theme/opacity không đụng
  (vẫn do app sync).

Hành vi từng nút:

- **Trackpad**: lật `trackpad` của kết nối đang hiển thị, lưu lại, pill đổi
  màu/trạng thái ngay.
- **Bàn phím**: lật `keyboard` tương tự.
- **Chuyển đổi**: chọn kết nối tiếp theo theo thứ tự hiển thị (yêu thích
  trước, rồi theo thứ tự lưu), quay vòng, lưu id mới vào
  `flutter.ace_widget_current_id`, widget đổi tên/host:port/trạng thái ngay.
  Chỉ hiện khi có > 1 kết nối (như bước 27).
- **Vùng thông tin**: vẫn là launch intent duy nhất mở app
  (`aceremote://connect/<id>`, hoặc `aceremote://open` khi chưa có kết nối).

### Nút chuyển native đọc/ghi SharedPreferences như thế nào — ĐÃ XÁC MINH TỪ SOURCE THẬT

Đây là điểm quan trọng nhất của bước này, vì giả định ban đầu (và cả ghi
chú trong brief) có thể sai. Đã đọc trực tiếp source của
`shared_preferences_android` 2.4.7 + `shared_preferences` 2.5.3 trong
`~/.pub-cache`:

**Kết luận: Kotlin đọc/ghi file XML cổ điển `FlutterSharedPreferences`,
KHÔNG phải DataStore.**

- App dùng `SharedPreferences.getInstance()` (legacy sync API). Nó đi qua
  `SharedPreferencesStorePlatform` → `SharedPreferencesAndroid` → pigeon
  `SharedPreferencesApi` → `LegacySharedPreferencesPlugin`
  (`android/src/main/java/.../LegacySharedPreferencesPlugin.java`), trong đó:
  `SHARED_PREFERENCES_NAME = "FlutterSharedPreferences"` và
  `preferences.edit().putString(key, value).commit()` — ghi key **nguyên văn**
  như Dart gửi.
- Phía Dart (`shared_preferences_legacy.dart`): `_setValue` tự thêm tiền tố
  `'flutter.'` vào key trước khi gửi (`prefixedKey = '$_prefix$key'`), và
  `getAll()` lọc theo tiền tố `'flutter.'`.
- Backend DataStore (`FlutterSharedPreferences.preferences_pb`, protobuf,
  key không tiền tố) CHỈ là mặc định của API **async**
  (`SharedPreferencesAsync` / `SharedPreferencesWithCache`, qua
  `SharedPreferencesAsyncApi` + `SharedPreferencesBackend`). App Ace Remote
  KHÔNG dùng API async cho prefs của nó, nên file DataStore không chứa dữ
  liệu kết nối. Kotlin mà đọc/ghi DataStore thì sẽ đọc nhầm chỗ trống.

**File/key thật mà Kotlin dùng** (xem hằng trong provider):

| File | Key | Kiểu | Nội dung |
|---|---|---|---|
| `FlutterSharedPreferences` | `flutter.rdp_connections` | String (JSON) | Danh sách `{id, name, host, port, trackpad, keyboard, favorite}` theo thứ tự lưu |
| `FlutterSharedPreferences` | `flutter.ace_widget_current_id` | String | id kết nối đang hiển thị |
| `FlutterSharedPreferences` | `flutter.ace_remote_v1_theme` | Long | 0 = theo điện thoại, 1 = sáng, 2 = tối (chỉ đọc, không sửa ở đây) |
| `FlutterSharedPreferences` | `flutter.ace_widget_opacity` | Long | 0–100 (chỉ đọc, không sửa ở đây) |
| `HomeWidgetPreferences` | `widget_name`, `widget_address`, `widget_status`, `widget_trackpad`, `widget_keyboard`, `widget_has_next`, `widget_connection_id` | như Dart sync | Trạng thái hiển thị của widget (ghi lại sau mỗi lần bấm native) |

Chi tiết triển khai:

- Đọc: `JSONArray` từ `flutter.rdp_connections`; record thiếu `id` thì bỏ;
  `trackpad` mặc định `false`, `keyboard` mặc định `true` (khớp Dart
  `RdpConnection.fromJson`); thứ tự hiển thị = yêu thích trước
  (`sortedWith(compareByDescending { favorite })`, stable — giữ nguyên thứ
  tự lưu trong nhóm), khớp `RdpConnectionStore.displayOrder()`.
- Ghi: `saveConnections()` serialize lại **đúng thứ tự lưu ban đầu**
  (không ghi theo thứ tự hiển thị), đủ 7 field mỗi record — không làm mất
  field nào. Ghi bằng `SharedPreferences.Editor.apply()` (per-key merge,
  không ghi đè các key khác; cập nhật ngay trong bộ nhớ của process nên lần
  đọc sau trong cùng process thấy ngay giá trị mới).
- Current id: nếu id đã lưu không còn trong danh sách (đã xóa trên app)
  thì dùng kết nối đầu tiên theo thứ tự hiển thị, và ghi lại id đó khi bấm
  nút (khớp logic "repair" của Dart `syncFromPrefs`).

### Lưu ý quan trọng — cache SharedPreferences phía Dart (cần follow-up Dart, KHÔNG sửa được từ native)

Dart `SharedPreferences` giữ cache trong RAM, nạp 1 lần lúc
`getInstance()` đầu tiên. Nếu app đang sống ở nền khi An bấm nút trên
widget, app vẫn thấy giá trị CŨ cho tới khi khởi động lại hoặc gọi
`prefs.reload()`. Hệ quả:

- **Config trên đĩa + hiển thị widget luôn đúng** (Kotlin ghi đúng file,
  widget vẽ lại ngay).
- **App đang chạy nền sẽ thấy giá trị cũ** (danh sách Home, cài đặt
  Trackpad/Bàn phím dùng cho phiên RDP) cho tới khi restart. Đặc biệt: bấm
  Trackpad trên widget rồi chạm vùng thông tin để kết nối — nếu app đang ở
  nền, phiên RDP mở ra có thể dùng cài đặt Trackpad cũ vì
  `_handleWidgetUri(connect)` đọc qua cache.
- **Không mất dữ liệu**: ghi của Kotlin là per-key merge; ghi của Dart cũng
  là per-key merge — không bên nào ghi đè toàn bộ file của bên kia. Chỉ có
  hiển thị trong app (đang chạy nền) là tạm thời cũ; widget tự sửa lại đúng
  ở lần bấm tiếp theo (Kotlin luôn đọc từ đĩa).
- **Follow-up cần làm (bước sau, phía Dart — ngoài phạm vi bước 29)**:
  gọi `prefs.reload()` trước `RdpConnectionStore.load()` trong
  `lib/main.dart` (đường `_handleWidgetUri`, `load()`) hoặc khi app resume
  (`didChangeAppLifecycleState` → `resumed`). Đây đúng là bài học đã có từ
  skill Thuốc Vui (mục 3.1): sau khi Kotlin sửa dữ liệu, Dart phải
  `reload()` mới thấy.

## 2. Bỏ nút "Kết nối"

- Xóa `widget_btn_connect` khỏi `ace_remote_widget.xml` (cả TextView và
  handler trong provider).
- Widget còn lại: vùng thông tin (chạm để kết nối) + nút Trackpad + nút
  Bàn phím + nút chuyển đổi.
- Khi chưa có kết nối: 2 pill ẩn, nút chuyển ẩn, vùng thông tin hiện
  "Chưa có kết nối" / "Mở app để thêm kết nối", chạm vào mở app
  (`aceremote://open`).
- Bố cục sau khi bỏ nút: hàng pill còn 2 nút, mỗi nút `weight 1`, cao
  44dp, khoảng cách giữa 2 nút 8dp (xem việc 3).

## 3. Làm đẹp widget (Material 3, hiện đại)

Thiết kế lại theo phong cách đã hiện đại hóa ở bước 23/24 (xanh ngọc
`#2BB3A3`, bo góc, phân cấp rõ). Giữ nguyên: kích thước 4x2, sáng/tối theo
app, opacity 0–100% (chỉ nền mang opacity, chữ/nút luôn đục — cơ chế bitmap
bo góc của bước 27 không đổi).

- **Vùng thông tin**: thêm ô icon 44×44dp nền xanh ngọc bo góc 12dp
  (`widget_icon_tile.xml`) với icon màn hình trắng
  (`ic_widget_monitor.xml`, Material `desktop_windows`). Tên máy 17sp bold
  nổi bật; host:port 12sp, trạng thái 11sp, màu phụ nhỏ hơn. Padding nội
  dung 10dp → 12dp; khoảng cách icon–chữ 10dp.
- **Nút chuyển đổi**: từ TextView chữ "⇄" thành ImageView tròn 40dp, nền
  xám nhạt theo theme (`widget_circle_off_light/dark.xml`), icon vector
  mũi tên đổi chỗ (`ic_widget_swap.xml`, Material `swap_horiz`, tint theo
  theme). Không còn ký tự "⇄" (bước 27 đã ghi chú font máy có thể hiện ô
  vuông).
- **Nút Trackpad / Bàn phím**: từ TextView thành pill container (LinearLayout)
  gồm icon + nhãn, cao 44dp. Icon vector riêng:
  `ic_widget_trackpad.xml` (khung trackpad bo góc + vạch bấm, stroke trắng),
  `ic_widget_keyboard.xml` (Material `keyboard`). Trạng thái rõ ràng:
  BẬT = nền xanh ngọc + icon/nhãn trắng; TẮT = nền xám theo theme +
  icon/nhãn màu muted (provider tint icon bằng `setColorFilter` và đổi màu
  nhãn bằng `setTextColor`).
- **Không đổi kích thước widget** (`ace_remote_widget_info.xml` không sửa).

## File đã đổi (CHƯA commit — parent tự commit sau khi bước 28 xong)

Chỉ file native của widget + doc này; không đụng `lib/`, `pubspec.yaml`,
`pubspec.lock`, `test/`, `.github/workflows/`, `android/app/build.gradle`,
`AndroidManifest.xml`:

- `android/app/src/main/kotlin/vn/aceremote/app/AceRemoteWidgetProvider.kt`
  (viết lại: `onReceive` chặn 3 action native, `handleNativeAction`,
  `mirrorDisplayState`, `refreshAllWidgets`, `bind` mới, `applyPill`;
  bỏ `HomeWidgetLaunchIntent` cho các nút, chỉ vùng thông tin dùng launch
  intent)
- `android/app/src/main/res/layout/ace_remote_widget.xml`
  (viết lại: icon tile, nút chuyển ImageView tròn, 2 pill icon+nhãn, bỏ
  nút "Kết nối")
- `android/app/src/main/res/drawable/widget_icon_tile.xml` (mới)
- `android/app/src/main/res/drawable/widget_circle_off_light.xml` (mới)
- `android/app/src/main/res/drawable/widget_circle_off_dark.xml` (mới)
- `android/app/src/main/res/drawable/ic_widget_monitor.xml` (mới)
- `android/app/src/main/res/drawable/ic_widget_swap.xml` (mới)
- `android/app/src/main/res/drawable/ic_widget_keyboard.xml` (mới)
- `android/app/src/main/res/drawable/ic_widget_trackpad.xml` (mới)
- `android/app/src/main/res/drawable/widget_pill_on.xml`
  (chỉ sửa comment: bỏ nhắc nút "Kết nối" đã xóa)
- `docs/rdp-step29-widget-native-buttons-remove-connect-redesign.md` (doc này)

## Kiểm chứng

- `flutter analyze`: **0 issue**.
- `flutter test`: **96/96 pass** (95 bước 27 + 1 bước 28; bước 29 không đổi
  Dart nên số test giữ nguyên).
- Tất cả file XML mới/sửa đều parse được (kiểm bằng XML parser); mọi
  `R.id.*` / `R.drawable.*` mà Kotlin và layout tham chiếu đều tồn tại.
- **Kotlin native chỉ compile được trên CI** (VM không build được Android
  native): cần xem kết quả build ở run #16. Rủi ro chính là
  `RemoteViews.setInt(..., "setColorFilter", ...)` và
  `setBackgroundResource` trên container — đều là pattern RemoteViews
  chuẩn (ImageView.setColorFilter(int) là public), nhưng chỉ CI mới chứng
  minh được.
- Token Codex: **0** (làm trực tiếp).

## Cách test tay trên Fold6 (bản run #16)

Chuẩn bị: cài bản run #16 (gỡ bản cũ rồi cài — vẫn ký debug key), mở app,
đảm bảo có ít nhất 2 kết nối đã lưu (thêm 1 kết nối nữa trong Home nếu chưa
có; có thể đặt 1 cái làm Yêu thích để kiểm tra thứ tự chuyển). Thêm widget
4x2 ra màn hình chính.

1. **Nút Trackpad đổi ngay trên widget, không mở app**: bấm pill
   "Trackpad" — pill đổi màu xanh ngọc/trắng ngay, trạng thái dưới tên đổi
   "Đã lưu • Trackpad"; app KHÔNG mở lên. Bấm lại — về "Chạm".
2. **Nút Bàn phím tương tự**: bấm pill "Bàn phím" — pill tắt, trạng thái
   thêm "• Ẩn bàn phím"; app KHÔNG mở lên. Bấm lại — hiện lại.
3. **Nút chuyển đổi**: bấm nút tròn (icon mũi tên đổi chỗ) — tên máy +
   host:port + trạng thái đổi sang kết nối tiếp theo ngay, app KHÔNG mở
   lên. Bấm tiếp tới hết danh sách — quay vòng về kết nối đầu. Nếu có 1
   kết nối yêu thích, thứ tự chuyển ưu tiên nó trước.
4. **Không còn nút "Kết nối"**: widget chỉ còn 2 pill + nút tròn; không có
   nút "Kết nối" nào.
5. **Chạm vùng thông tin mới mở app**: chạm vào tên máy/host — app mở và
   kết nối thẳng tới đúng kết nối đang hiển thị trên widget.
6. **Config được lưu thật**: sau khi bấm Trackpad/Bàn phím trên widget,
   mở app → Home → Edit kết nối đó — công tắc Trackpad/Bàn phím phải khớp
   trạng thái vừa bấm trên widget. (Lưu ý: nếu app đang chạy nền lúc bấm,
   mở app có thể thấy giá trị cũ do cache Dart — xem mục 1; tắt hẳn app
   rồi mở lại thì luôn đúng. Follow-up `reload()` sẽ sửa hẳn.)
7. **Widget đẹp hơn**: icon tile xanh ngọc + icon màn hình trắng, nút
   tròn với icon mũi tên đổi chỗ (không còn ký tự "⇄"), 2 pill có icon +
   nhãn, trạng thái bật/tắt rõ ràng. Kiểm tra cả sáng và tối (đổi theme
   trong Cài đặt → widget đổi theo) và opacity (kéo slider trong Cài đặt
   → nền widget mờ dần, chữ/nút vẫn đục).

## Ghi chú cho run #16

- Mục `1.5.0+16` trong `CHANGELOG.md` (bước 28) cần thêm thay đổi của bước
  29 trước khi push, nếu không release notes sẽ không nhắc tới sửa widget.
- Bản run #16 vẫn ký debug key → An phải gỡ bản cũ rồi cài; sau bản này
  (khi fixed key xong) mới cập nhật tại chỗ được.
