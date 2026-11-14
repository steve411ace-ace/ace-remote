# Bước 31 — Widget: bo góc 28dp như Thuốc Vui, chạm đâu cũng mở app, app theo kịp nút widget

Base: commit VM `25c7cf7` (bước 30). An test bản run #16 (1.5.0 (16)) trên Fold6,
gửi ảnh widget và báo 3 ý (vấn đề 1 về gỡ/cài đã được giải thích riêng — bản
run #16 đổi chữ ký nên phải gỡ/cài 1 lần cuối, đã kiểm chứng chữ ký fixed key
khớp; từ run #17 trở đi mới bấm "Cập nhật" tại chỗ được):

1. "widget vẫn xấu, bo tròn phía ngoài không đều, làm bo ít lại bo như app
   thuoc vui đó."
2. "ko chạm mở đc, tôi muốn chạm đâu ngoài 2 nút bấm kia đều mở app vào kết
   nối" (nút chuyển đổi giữ chức năng chuyển ngay trên widget).
3. "Thêm nữa nút bên ngoài bấm mà bên trong ko effect theo" — bấm nút trên
   widget đổi trạng thái đúng, nhưng mở màn hình "Sửa kết nối" trong app thì
   vẫn hiện giá trị CŨ.

## Việc 1 — Bo góc ngoài: 28dp, đều, viền 1dp (chuẩn Thuốc Vui)

Chuẩn Thuốc Vui (skill `lam-app-moi-chuan-thuoc-vui` mục 3.3): "Viền widget
1dp, bo góc 28dp là chuẩn đã duyệt".

### Nguyên nhân bo không đều (đã đo từ ảnh An gửi)
- Nền widget là bitmap cố định **400×200** (tỉ lệ 2:1), vẽ bo `BG_RADIUS = 48px`,
  hiển thị bằng `ImageView` với `scaleType="fitXY"` (kéo giãn cho vừa khung).
- Widget thật trên Fold6 KHÔNG phải 2:1 — đo từ ảnh An gửi, widget rộng ~740px,
  cao ~300px (tỉ lệ ~2.5:1). `fitXY` kéo giãn không đều 2 chiều (ngang ×1.85,
  dọc ×1.5) nên góc bo thành hình ellipse: bán kính ngang ~38dp, dọc ~31dp —
  vừa quá tròn, vừa lệch nhau ("bo không đều").
- Tính lại: 48px trên bitmap → ~89×72px trên màn hình → ~38×31dp (mật độ
  Fold6 ~2.34x), trong khi chuẩn Thuốc Vui chỉ 28dp.

### Cách sửa (`AceRemoteWidgetProvider.kt`, hàm `roundedBackground` mới)
- Bitmap được vẽ theo **tỉ lệ thật của widget**, lấy từ
  `AppWidgetManager.getAppWidgetOptions(appWidgetId)` (max width/height, dp,
  theo hướng màn hình hiện tại); fallback về 250×110dp (kích thước khai báo
  trong `ace_remote_widget_info.xml`) khi không lấy được. Tỉ lệ được kẹp trong
  [1.5, 3.5] để chống giá trị lỗi.
- Chiều rộng bitmap cố định 480px (~380 KB tối đa, an toàn dưới giới hạn
  parcel của RemoteViews); chiều cao = 480 / tỉ lệ, kẹp [160, 320]. Vì tỉ lệ
  bitmap khớp tỉ lệ widget thật nên `fitXY` kéo giãn đều cả 2 chiều → góc bo
  tròn đều, không còn ellipse.
- Bán kính và viền tính từ dp (mật độ tự triệt tiêu):
  `radiusPx = 28 * bitmapWidth / widgetWidthDp`,
  `strokePx = max(1, 1 * bitmapWidth / widgetWidthDp)` → trên màn hình đúng
  28dp góc bo và 1dp viền, ở mọi mật độ và kích thước widget.
- Viền 1dp vẽ bằng stroke nằm gọn trong mép nền (inset nửa stroke, bán kính
  trong trừ tương ứng) nên không bị cắt. Màu viền nhẹ: trắng 12% (nền tối),
  đen 10% (nền sáng); alpha của viền nhân với opacity của nền nên widget trong
  suốt 0% thì viền cũng biến mất. Opacity 0–100% và sáng/tối theo app giữ
  nguyên.
- `onUpdate` giờ truyền `appWidgetManager` + `appWidgetId` vào `bind()` để
  vẽ nền theo đúng kích thước từng instance.

## Việc 2 — Chạm bất cứ đâu (trừ 3 nút) đều mở app và kết nối

### Nguyên nhân chạm KHÔNG mở được (đã chứng minh từ source thật)
Bước 29 gắn tap mở app vào view `widget_info` bằng intent tự chế:
`Intent(Intent.ACTION_VIEW, Uri.parse("aceremote://connect/<id>"))` + `package`.
Chết ở 2 chỗ, cả 2 đều đã đối chiếu source plugin `home_widget` 0.10.0
(`.pub-cache/hosted/pub.dev/home_widget-0.10.0/android/...`):

1. **Intent không resolve được (lỗi chính).** `ACTION_VIEW` với scheme tự
   chế `aceremote` là implicit intent — muốn tới được `MainActivity` thì
   `MainActivity` phải có intent-filter `ACTION_VIEW` + `<data
   android:scheme="aceremote"/>`. `AndroidManifest.xml` KHÔNG có filter này
   (chỉ có MAIN/LAUNCHER và `es.antonborri.home_widget.action.LAUNCH`). Nên
   chạm vào là hệ thống không tìm được activity nào → không mở gì cả.
2. **Dù có resolve được thì Dart cũng không nhận được URI.** Plugin chỉ giao
   URI cho Dart khi intent action là `es.antonborri.home_widget.action.LAUNCH`
   (`HomeWidgetPlugin.kt:165` — `initiallyLaunchedFromHomeWidget`, và `:397` —
   `widgetClicked` stream). Intent `ACTION_VIEW` không qua được 2 cửa này →
   app có mở cũng không biết phải kết nối tới máy nào.

Đây là hồi quy từ bước 29: bước 27 dùng đúng cơ chế LAUNCH của plugin (đã
chạy được ở run #15); bước 29 viết lại provider và đổi sang `ACTION_VIEW`
mà không thêm filter → hỏng.

### Cách sửa (`AceRemoteWidgetProvider.kt`, hàm `bind`)
- Dùng đúng helper của plugin: `HomeWidgetLaunchIntent.getActivity(context,
  MainActivity::class.java, openUri)` — intent tường minh tới `MainActivity`,
  action LAUNCH, URI làm data (`aceremote://connect/<id>`, hoặc
  `aceremote://open` khi chưa có kết nối). Helper này còn xử lý sẵn quyền mở
  activity từ widget trên Android 14+ (`ActivityOptions`
  `MODE_BACKGROUND_ACTIVITY_START_ALLOWED`). Plugin giao URI cho Dart qua
  `initiallyLaunchedFromHomeWidget` / `widgetClicked` như bước 27.
- Gắn PendingIntent mở app lên **layout gốc `widget_root`** (thay vì
  `widget_info`): `views.setOnClickPendingIntent(R.id.widget_root, ...)`.
  Trong RemoteViews, tap lên view con nào không có handler riêng sẽ nổi bọt
  lên handler của view cha gần nhất có handler → chạm icon tile, tên máy,
  host:port, trạng thái, khoảng trống, nền — tất cả đều mở app và kết nối.
  Chỉ 3 nút giữ handler riêng (broadcast, không mở app): 2 pill Trackpad /
  Bàn phím (requestCode 101/102) và nút chuyển đổi (103). Handler cũ trên
  `widget_info` đã xóa (thừa).
- Không cần sửa manifest (intent tường minh tới `MainActivity`, filter LAUNCH
  đã có từ bước 27) và không cần sửa Dart cho việc này
  (`_handleWidgetUri` đã nhận đúng URI qua plugin).

## Việc 3 — App theo kịp nút widget (`prefs.reload()`)

### Nguyên nhân
Dart `SharedPreferences` cache trong RAM, nạp 1 lần lúc `getInstance()`.
Kotlin trên widget ghi thẳng vào file XML `FlutterSharedPreferences` trên
đĩa, không qua Dart. App đang sống ở nền khi An bấm nút widget thì cache RAM
vẫn giữ giá trị CŨ tới khi restart hoặc `reload()` — đúng bài học Thuốc Vui
skill §3.1 (lỗi v1.2.13/v1.2.14) và đúng caveat đã ghi trong doc bước 29.
Hậu quả đúng như ảnh An gửi: widget hiện "Đã lưu • Chạm • Ẩn bàn phím"
(2 pill xám TẮT) nhưng màn hình "Sửa kết nối" trong app vẫn hiện toggle
Trackpad BẬT + Hiện bàn phím BẬT.

### Cách sửa (`lib/main.dart`)
- `_AceAppState._loadConnectionsFresh()` (mới): `prefs.reload()` rồi mới
  `RdpConnectionStore().load()`. Dùng thay cho `store.load()` trong mọi
  nhánh của `_handleWidgetUri` (connect / toggle / next) — nhánh toggle tuy
  giờ là code dự phòng (nút widget đã xử lý native từ bước 29) nhưng vẫn
  được bảo vệ: `store.update()` sau đó đọc lại từ cache đã reload nên không
  ghi đè mất thay đổi của widget.
- `_AceAppState.didChangeAppLifecycleState` khi `resumed`: gọi
  `_refreshOnResume()` — `prefs.reload()` rồi tăng `_resumeTick`
  (ValueNotifier<int> mới). `Home` nhận `resumeTick` (param tùy chọn) và
  `_HomeState` lắng nghe để gọi `_reload()` mỗi khi app quay lại từ nền.
- `_HomeState._reload()`: `SharedPreferences.getInstance()` + `reload()`
  TRƯỚC `store.load()` — mọi lần Home tải lại danh sách (mở app, sau khi
  thêm/sửa/xóa/yêu thích, khi resume) đều đọc từ đĩa. Nhờ vậy màn hình
  "Sửa kết nối" mở từ Home luôn thấy giá trị mới nhất.
- `_AceAppState.dispose()` dispose `_resumeTick`; `_HomeState.dispose()`
  gỡ listener.

### Lưu ý khi test (rút ra từ source thật của plugin)
`SharedPreferences.setMockInitialValues` KHÔNG mô phỏng được ghi ngoài:
nó đặt `_completer = null` (xem `shared_preferences-2.5.3`
`shared_preferences_legacy.dart:279-293`), nên lần `getInstance()` sau đó
tạo instance mới với dữ liệu mới ngay — không cần `reload()` cũng thấy.
Test phải ghi thẳng vào store nền qua
`SharedPreferencesStorePlatform.instance.setValue('String',
'flutter.rdp_connections', json)` — đúng như Kotlin ghi file. Test dùng
import này kèm `// ignore: depend_on_referenced_packages` (chỉ dùng trong
test, không đổi `pubspec.yaml`).

## File đổi
- `android/app/src/main/kotlin/vn/aceremote/app/AceRemoteWidgetProvider.kt`
  (bo 28dp + viền 1dp theo tỉ lệ thật; tap mở app gắn lên `widget_root`
  bằng `HomeWidgetLaunchIntent`; xóa handler `ACTION_VIEW` trên `widget_info`)
- `android/app/src/main/res/layout/ace_remote_widget.xml` (chỉ comment:
  tap giờ nằm ở root)
- `lib/main.dart` (`_resumeTick`, `_refreshOnResume`,
  `_loadConnectionsFresh`, `_handleWidgetUri` dùng load mới, `Home.resumeTick`,
  `_HomeState` lắng nghe tick + `_reload()` gọi `reload()` trước)
- `test/rdp_connections_test.dart` (2 test mới cho việc 3, xem dưới)
- `docs/rdp-step31-widget-corners-tap-open-reload.md` (file này)

Không đụng: `pubspec.yaml` (version vẫn 1.5.0+16), workflow, `build.gradle`,
`debug.keystore.base64`, `CHANGELOG.md` (parent thêm bullet bước 31 sau),
logic lưu trữ bước 23, code RDP, deep link Dart (không cần đổi).

## Kiểm chứng (trên VM)
- `flutter analyze`: **0 issue**.
- `flutter test`: **98/98 pass** (96 cũ + 2 mới cho việc 3).
- Test mới 1 — `load sees values changed on disk after reload, without
  restart`: ghi đè JSON trên store nền (trackpad false → true), `load()` vẫn
  thấy cũ, sau `reload()` mới thấy mới.
- Test mới 2 — `Home reloads its list when the app resumes after a widget
  tap` (widget test): thêm 1 kết nối trên store nền khi app ở nền, trước
  tick Home vẫn hiện danh sách cũ, tăng `resumeTick` → Home tải lại từ đĩa,
  kết nối mới hiện ra.
- Kotlin native chỉ compile được trên CI — cần xem kết quả build ở run #17
  (rủi ro chính: `HomeWidgetLaunchIntent.getActivity` với `MainActivity`,
  và `getAppWidgetOptions` trên launcher của Fold6).

## Test tay trên Fold6 (sau khi cài run #17)
1. **Bo góc:** nhìn widget trên màn hình chính — 4 góc bo vừa phải (28dp,
   rõ ràng ít tròn hơn bản run #16), 4 góc đều nhau, có viền mỏng 1dp ôm
   sát mép. Đổi theme Sáng/Tối trong app → widget đổi theo, bo/viền giữ
   nguyên. Kéo slider trong suốt 0–100% → nền mờ dần, viền mờ theo.
2. **Chạm mở app:** chạm lần lượt icon tile, tên máy, host:port, dòng trạng
   thái, khoảng trống giữa các hàng → mỗi lần app đều mở và kết nối thẳng
   tới máy đó. Chạm 2 pill Trackpad/Bàn phím → chỉ đổi trạng thái trên
   widget, KHÔNG mở app. Chạm nút chuyển đổi → chỉ chuyển máy trên widget,
   KHÔNG mở app. Xóa hết kết nối → chạm đâu trên widget cũng mở app.
3. **App theo kịp widget:** bấm nút Trackpad trên widget (đổi sang Chạm
   hoặc Trackpad), mở app ngay → vào "Sửa kết nối" của máy đó → toggle
   "Chế độ Trackpad" phải theo đúng trạng thái vừa bấm trên widget (không
   còn hiện giá trị cũ). Làm tương tự với nút Bàn phím (toggle "Hiện bàn
   phím"). Mở app từ đa nhiệm sau khi bấm nút widget cũng phải thấy đúng.
