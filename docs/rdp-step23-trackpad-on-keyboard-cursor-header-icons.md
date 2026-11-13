# Bước 23 — Trackpad trên bàn phím, con trỏ chuột, ẩn hết nút + config ra màn hình chính, nhiều kết nối đã lưu

Phản hồi của An khi test bản run #10 (14/11/2026 03:38–03:45, kèm ảnh chụp Fold6)
trên bản bước 21: lưu username + mật khẩu, không PIN, header tự ẩn sau 3 giây,
chế độ Trackpad (mặt đen trống), nút ẩn/hiện bàn phím. 6 việc dưới đây sửa đúng
những phản hồi đó. Base: commit `07911ee` (bước 22, Caps Lock toggle).
Làm trực tiếp, không chạy Codex CLI (lỗi sandbox) — token Codex: 0.

## Thiết kế đổi hướng (04:03 — sửa lại việc 3 + việc 4)

An gửi ảnh app Microsoft Remote Desktop với menu long-press trên thẻ "ACE"
(Connect / Favorite / Edit / Delete) và nói: "Nút trackpad, bàn phím em ẩn
hết đi em. Cho config ở màn hình này luôn. Cần anh trở ra. Chọn giữ rồi nhấn
edit để chỉnh xong vào lại. Khỏi để nút vướng tầm nhìn. ở chỗ edit này cho
config kết nối, port, user, pass luôn."

→ **Màn hình remote KHÔNG còn nút nào cả** (xem việc 3 mới). Chế độ
Trackpad/Chạm + Ẩn/Hiện bàn phím thành **cài đặt của từng kết nối**, chỉnh
trong màn hình Edit (xem việc 6). Việc 3 cũ (nút toggle chevron bật/tắt
header bằng tay) và việc 4 cũ (icon hiện đại cho nút header) BỎ — không còn
header để bật/tắt hay hiện đại hóa nữa; việc 4 đổi thành hiện đại hóa Home +
menu long-press + màn hình Edit theo mẫu Microsoft Remote Desktop.

## 1. Trackpad lướt TRÊN BÀN PHÍM (không còn mặt đen trống)

Vấn đề: ở chế độ Trackpad, nửa dưới thành mặt đen trống chỉ có chữ "Trackpad /
Kéo để di chuột…". An muốn lướt trực tiếp trên các phím (phím vẫn hiện).

- Xóa toàn bộ class `RdpTrackpad` (`lib/main.dart`); layout RDP luôn hiện
  `keyboardPanel()` (bỏ `ValueListenableBuilder` trackpadMode khỏi layout).
- Thêm wrapper `keyboardSwipe(Widget child)` — một `Listener`
  (HitTestBehavior.translucent) bọc bàn phím, hoạt động ở CẢ hai chế độ:
  - Kéo 1 ngón > 12 px logic → `moveRelative(delta * dpr)` (di chuột tương
    đối, hệ số nhạy 1.5x ở native như cũ), KHÔNG kích hoạt phím.
  - Chạm nhanh vào phím → gõ phím bình thường.
  - Chạm 2 ngón đứng yên → click phải tại điểm giữa 2 ngón; kéo 2 ngón →
    cuộn (48 px / 1 notch).
  - Cờ `kbSuppressKey`: lần bấm phím kết thúc một lần lướt / cử chỉ 2 ngón
    bị bỏ qua (tap recognizer vẫn có thể bắn cho lần kéo ngắn); cờ được xóa ở
    lần pointer-down tiếp theo.
- `press()` (nhánh RDP) kiểm tra `kbSuppressKey` trước: nếu có cờ thì bỏ qua
  lần bấm đó và xóa cờ.
- State mới cạnh `capsLockOn`: `kbSwipePoints`, `kbSwipeDistance`,
  `kbSwipeDownTime`, `kbSwipeTwoFinger`, `kbSwipeScrollAccum`,
  `kbSwipeTwoFingerTravel`, `kbSwipeTwoFingerCenter`, `kbSuppressKey`.

## 2. Hiện con trỏ chuột trên màn hình remote

Nguyên nhân: FreeRDP gửi hình con trỏ qua callback `OnPointerSet`, nhưng app
bỏ qua — cả 3 callback `OnPointerSet` / `OnPointerSetNull` /
`OnPointerSetDefault` trong `RdpPlugin.kt` đều là hàm rỗng `{}`. Ngoài ra
`draw()` chỉ chạy khi có cập nhật đồ họa, không chạy khi con trỏ di chuyển,
nên dù có vẽ thì con trỏ cũng không cập nhật theo chuột.

- `RdpPlugin.kt`: thêm field `pointerBitmap` / `pointerHotX` / `pointerHotY`.
  `OnPointerSet` lưu bitmap từ pixels (ARGB_8888) + hotspot rồi gọi `draw()`;
  `OnPointerSetNull` / `OnPointerSetDefault` xóa bitmap rồi gọi `draw()`
  (vẽ mũi tên mặc định). `stop()` và `finish()` xóa `pointerBitmap`.
- `render()`: snapshot vị trí + hình con trỏ dưới lock; vẽ bitmap con trỏ tại
  `lastX`/`lastY` (đổi sang tọa độ surface theo aspect-fit, trừ hotspot),
  hoặc vẽ mũi tên mặc định khi không có hình (`drawDefaultCursor`: mũi tên
  trắng viền đen 26 px, Paint `cursorArrowFill` / `cursorArrowOutline`).
- Nhánh MOVE trong `cursorInput` gọi `draw()` (đã debounce) để con trỏ vẽ lại
  theo mỗi lần di chuyển — ở cả hai chế độ, đặc biệt Trackpad.

## 3. Ẩn HẾT nút trên màn hình remote — thoát bằng Back (thiết kế mới 04:03)

Thay cho việc 3 cũ (nút toggle chevron bật/tắt header bằng tay — đã bỏ, không
còn header để bật/tắt):

- Màn hình remote khi đã kết nối KHÔNG còn nút nào: không nút Trackpad/Chạm,
  không nút Ẩn/Hiện bàn phím, không nút Ngắt kết nối, không nút toggle
  chevron/header, không chip "Đã kết nối". Chỉ có màn hình desktop ở trên +
  bàn phím laptop ở dưới, sạch, không nút nào vướng tầm nhìn.
- `lib/rdp_surface.dart`: bỏ `headerVisible`, `toggleHeader()`,
  `toggleTrackpadMode()`, `toggleKeyboardVisible()`; nhánh `connected` trong
  `build()` trả về `SizedBox.shrink()` (chỉ còn surface remote).
- Thoát/kết thúc phiên: nút **Back / cử chỉ vuốt back của Android** để trở ra
  màn hình chính. `RemotePage` bọc `Scaffold` trong `PopScope(canPop: true,
  onPopInvokedWithResult: ...)` — khi pop thành công và đang ở chế độ RDP thì
  gọi `rdpController.disconnect()` (tin nhắn `disconnect` được gửi đi đồng bộ
  khi gọi, nên vẫn tới được native trước khi trang bị dispose). `canPop`
  luôn true nên Back không bao giờ kẹt; Home nằm dưới route này nên Back
  không thoát hẳn app. Ở chế độ agent, Back chỉ pop bình thường (không gọi
  disconnect RDP).
- Chế độ Trackpad/Chạm + Ẩn/Hiện bàn phím không còn là nút lúc đang remote —
  thành cài đặt của từng kết nối, chỉnh trong màn hình Edit (việc 6). Muốn
  đổi: trở ra Home → mở Edit → chỉnh → bấm vào kết nối để vào lại.

## 4. Icon hiện đại — Home + menu long-press + màn hình Edit (thiết kế mới 04:03)

Thay cho việc 4 cũ (icon hiện đại cho nút header — đã bỏ, không còn nút
header). Mẫu vẫn là app Microsoft Remote Desktop An gửi: dark theme sạch,
thanh trên có icon người dùng tròn + tiêu đề "Devices" + icon "+" và kính lúp;
mục "PC Connections" với chevron; thẻ card bo góc lớn với ảnh nền Windows 11
+ chữ "ACE" / "ACE\steve"; bottom navigation 3 tab.

- **Màn hình Home** (`lib/main.dart`): danh sách kết nối dạng card — mỗi card
  có dải header gradient xanh ngọc (`0xff1d7f73`) → xanh dương (`0xff2b6cb0`)
  với tên máy (20, w600, trắng) + `host:port` (13, white70) + icon sao vàng
  khi là Favorite; hàng dưới: icon người + username (hoặc "Chưa có tài khoản
  — bấm để nhập"). Tiêu đề mục "Kết nối đã lưu" (kiểu "PC Connections" của
  app mẫu). AppBar "Ace Remote" + nút "+" (tooltip "Thêm kết nối") + Cài đặt
  (`Icons.settings_outlined`).
- **Menu long-press** (`_showConnectionMenu`): chọn giữ (long-press) một card
  thì hiện menu ngữ cảnh `showMenu` neo tại vị trí card, 4 mục icon + chữ
  như ảnh mẫu: Connect (`Icons.play_circle_outline`), Favorite
  (`Icons.star_outline` / `Icons.star`, label "Favorite" / "Bỏ yêu thích"),
  Edit (`Icons.edit_outlined`), Delete (`Icons.delete_outline`).
- **Màn hình Edit** (`_ConnectionEditorPage`): màn hình đầy đủ (không phải
  dialog) với AppBar "Thêm kết nối" / "Sửa kết nối", các trường Tên hiển thị /
  Host / Port / Username / Mật khẩu, 2 công tắc `SwitchListTile` ("Chế độ
  Trackpad", "Hiện bàn phím"), nút "Lưu" đầy chiều rộng.
- **Bàn phím laptop**: làm mới kiểu phím, giữ nguyên bố cục + chữ trên phím —
  borderRadius 8 (trước 4), màu phím mặc định `0xff32353c` (trước
  `0xff292b30`), viền `0xff4a4d55` (trước `0xff3c3e43`), phím được chọn
  (modifier armed / Caps bật) màu xanh ngọc `0xff2bb3a3` (trước `0xff505762`),
  màu khi nhấn `0xff8b929e` giữ nguyên.
- Chức năng tất cả các nút/phím giữ nguyên, chỉ đổi diện mạo.

## 5. Kết nối khi mở lại app quá lâu

Vấn đề: mở lại app, bấm kết nối, hộp thoại "Đang kết nối…" hiện lâu mới xong.

Điều tra (luồng `RdpConnectionPane.connect()` → `RdpController.connect()` →
`RdpPlugin.kt`): các bước là tạo session (`GlobalApp.createSession`),
`setConnectionInfo`, `connect` (NLA), rồi chờ frame đầu (`OnSettingsChanged`
tạo bitmap). Không có bước nào thừa trong code Dart: delay 400 ms duy nhất là
delay cố ý của bước 19 (để bàn phím mềm ẩn và layout ổn định rồi `start()`
mới đọc đúng kích thước SurfaceView). Phần chậm còn lại nằm ở phía
RDP/NLA/mạng (bản chất giao thức, không rút ngắn được từ app), nên bước này
tập trung vào đo đạc + trải nghiệm:

- `RdpPlugin.kt`: handler "connect" đặt `connectStartedAt`,
  `connectPhase = "creating"`, `firstFrameLogged = false`,
  `Log.d "connect: creating session"`; `snapshot()` thêm `"phase"`; `start()`
  log sau createSession / setConnectionInfo / connect() kèm số ms đã trôi;
  `OnPreConnect` đặt phase = "connecting" + log; `OnAuthenticate` đặt
  phase = "auth" + log + `change("connecting")`; `OnConnectionSuccess` xóa
  phase + log số ms; `OnSettingsChanged` log "first frame" 1 lần khi bitmap
  trước đó là null. Xem logcat với tag `AceRdp` để biết bước nào chậm nhất
  (tạo session / NLA / chờ frame đầu).
- `lib/rdp_surface.dart`: busy UI hiện chữ theo phase:
  "Đang xác thực…" / "Đang tạo phiên…" / "Đang kết nối…" /
  "Đang ngắt kết nối…", lấy từ `status['phase']`; nút "Ngắt" vẫn bấm được để
  hủy khi đợi lâu. `connect()` thêm
  `debugPrint('AceRdp: connect tapped, waiting 400ms for layout')` trước
  delay 400 ms.

## 6. Nhiều kết nối đã lưu (như "PC Connections" trong app mẫu)

An: "Sẵn cho phép thêm nhiều kết nối nha em. Config userpass trên chỗ này
luôn. Bấm vào là kết nối." Màn hình chính giờ là danh sách kết nối, không
còn thẻ agent đơn lẻ (trong bản RDP, nút "Kết nối" của thẻ cũ vốn đã mở trang
RDP; địa chỉ agent vẫn chỉnh + kiểm tra được trong Cài đặt).

### Lưu trữ

File mới `lib/rdp_connections.dart` (`RdpConnection`, `RdpConnectionStore`):

- **SharedPreferences, key `rdp_connections`**: JSON list các bản ghi hiển
  thị `{id, name, host, port, trackpad, keyboard, favorite}`. Username KHÔNG
  nằm trong JSON này. `trackpad` (false = chạm, true = trackpad),
  `keyboard` (false = ẩn bàn phím, true = hiện), `favorite` (ghim lên đầu
  danh sách) — bản ghi cũ thiếu các key này thì nhận mặc định (chạm / hiện /
  không yêu thích), không cần migrate. Id tạo bằng
  `millisecondsSinceEpoch` + bộ đếm tăng (`_nextId`) để 2 kết nối thêm cùng
  1 mili-giây vẫn khác id (id trùng làm hỏng update/remove/favorite).
- **Secure storage** (cùng file mã hóa `ace_rdp_credentials` như bước 21,
  `encryptedSharedPreferences=true`): `rdp_username_<id>` và
  `rdp_password_<id>` cho từng kết nối — mật khẩu không bao giờ nằm plaintext
  trong prefs; xóa kết nối thì xóa luôn 2 key này.
- **Mặc định ban đầu**: lần chạy đầu (chưa có key `rdp_connections`) seed 1
  kết nối `ace — Windows`, host `100.101.127.41`, port `3389` (id `ace`).
  Nếu bước 21 đã lưu username/mật khẩu (key toàn cục `rdp_username` /
  `rdp_password`), seed copy chúng sang key của kết nối `ace` để An bấm vào
  là kết nối ngay, không phải nhập lại. Xóa hết kết nối thì danh sách trống
  vẫn trống (không seed lại).
- Thứ tự lưu trong prefs giữ nguyên thứ tự thêm; chỉ danh sách hiển thị
  (`load()`) mới xếp Favorite lên đầu (sort ổn định). `add`/`update`/
  `remove` đọc/ghi qua `_loadRaw()` (không sort) để thứ tự lưu không bị
  xáo khi sửa.

### Luồng dùng

- **Home** (`lib/main.dart`, `_HomeState`): AppBar "Ace Remote" + nút
  "+" (tooltip "Thêm kết nối") + Cài đặt; tiêu đề mục "Kết nối đã lưu"; mỗi
  kết nối là 1 card (dải header gradient xanh ngọc → xanh dương với tên máy
  + `host:port` + sao vàng nếu Favorite; hàng dưới: icon người + username,
  hoặc "Chưa có tài khoản — bấm để nhập"). Bấm vào card là kết nối ngay.
- **Long-press card** → menu ngữ cảnh (`_showConnectionMenu`, `showMenu`
  neo tại vị trí card): Connect / Favorite / Edit / Delete. Favorite đổi cờ
  `favorite` và xếp card đó lên đầu danh sách (kèm sao vàng); Edit mở màn
  hình Edit; Delete hỏi xác nhận rồi xóa (cả mật khẩu đã lưu); Connect thì
  vào ngay như bấm vào card.
- **Thêm/Sửa** (`_ConnectionEditorPage` — màn hình đầy đủ, không phải
  dialog): 5 trường Tên hiển thị / Host / Port / Username / Mật khẩu
  (obscureText) + 2 công tắc: "Chế độ Trackpad" (bật: lướt trên bàn phím để
  di chuột; tắt: chạm trực tiếp) và "Hiện bàn phím" (tắt: màn hình remote
  chiếm toàn bộ màn hình khi kết nối). Khi sửa, trường mật khẩu được điền
  sẵn mật khẩu đã lưu (nút Lưu bị khóa trong lúc đang tải mật khẩu để không
  vô tình xóa trắng); kiểm tra tên + host không rỗng, port 1–65535. Lưu xong
  thì về lại Home; bấm vào card (hoặc Connect trong menu) để vào lại với cài
  đặt mới.
- **Bấm vào card** → `RemotePage(rdpMode: true, rdpConnection: connection)`.
  `RdpConnectionPane(initialConnection: ...)` điền sẵn host/port, tải
  user/pass của kết nối đó; nếu đủ cả hai thì **tự kết nối luôn** (không cần
  nhập lại). Nếu chưa đủ (chưa lưu user/pass) thì hiện form đã điền sẵn
  host/port để An nhập. Form vẫn cho sửa user/pass khi cần; khi kết nối
  thành công, user/pass (kể cả đã sửa) được lưu lại vào key của kết nối đó
  (qua `RdpConnectionStore.saveCredentials`, trong `connectionChanged()`)
  VÀ vào key toàn cục bước 21 như cũ. Khi ngắt/thất bại, form điền lại từ
  kết nối đó (không tự kết nối lại — tránh vòng lặp thất bại).
- **Áp dụng cài đặt Trackpad/bàn phím**: pane áp dụng cài đặt của kết nối
  trong `addPostFrameCallback` sau frame đầu (`setTrackpadMode` +
  `setKeyboardVisible`) — đặt trực tiếp trong `initState` sẽ báo lỗi
  "markNeedsBuild during build" vì layout của RemotePage đang build mà
  `keyboardVisible` đã notify listener. `setTrackpadMode` gửi lại mode khi
  attach nếu channel chưa sẵn.
- `RemotePage` thêm tham số `rdpConnection` (nullable), truyền xuống pane.

## File đổi

| File | Đổi |
|---|---|
| `lib/main.dart` | Bỏ `RdpTrackpad`; `keyboardSwipe()` + state lướt; phím hiện đại (màu/bo góc); Home mới theo mẫu (gradient header) + danh sách kết nối + menu long-press (Connect/Favorite/Edit/Delete) + màn hình Edit đầy đủ (5 trường + 2 công tắc Trackpad/bàn phím); `RemotePage` bọc `PopScope` (Back → ngắt kết nối, về Home); `RemotePage.rdpConnection`; pane nhận `initialConnection` |
| `lib/rdp_surface.dart` | Bỏ header (không còn nút nào khi đã kết nối — bỏ `headerVisible`, `toggleHeader`, `toggleTrackpadMode`, `toggleKeyboardVisible`); pane áp dụng cài đặt Trackpad/bàn phím của kết nối qua `addPostFrameCallback`; pane nhận `initialConnection`, tự kết nối khi đủ user/pass, lưu lại vào kết nối khi thành công |
| `lib/rdp_connections.dart` | **Mới**: model + store (prefs JSON + secure storage theo id; thêm `trackpadMode`, `keyboardVisible`, `favorite`; id duy nhất bằng timestamp + bộ đếm; `_loadRaw` giữ thứ tự thêm, `load()` xếp Favorite lên đầu) |
| `android/.../RdpPlugin.kt` | Vẽ con trỏ (OnPointerSet + mũi tên mặc định, draw() khi di chuyển); log thời gian/phase từng bước kết nối |
| `test/rdp_surface_test.dart` | Viết lại test header → test màn hình remote không còn nút nào; test pane áp dụng đúng cài đặt Trackpad/bàn phím của kết nối; cập nhật 2 test cũ còn mong đợi pill "Đã kết nối" / nút "Ngắt kết nối"; cập nhật màu phím mới; test trackpad (bàn phím vẫn hiện, lướt → moveRelative, chạm → gõ phím, 2 ngón → click phải) |
| `test/remote_test.dart` | Cập nhật màu phím mặc định `0xff292b30` → `0xff32353c`; thêm `setUp` mock SharedPreferences + secure storage (Home tải danh sách kết nối — không mock thì `_reload()` không bao giờ xong, spinner quay mãi, `pumpAndSettle` timeout) |
| `test/rdp_connections_test.dart` | **Mới**: 7 test store + 7 test widget (xem dưới) |

Không đụng: fixed key (`build.gradle`, 2 workflow), `proguard-rules.pro`,
PIN, logic Caps Lock bước 22, logic lưu username/mật khẩu toàn cục bước 21.

## Kiểm chứng (VM, Flutter 3.50.0)

- `flutter analyze`: **0 issue**.
- `flutter test`: **57/57 pass** (agent 10 + remote 19 + rdp_surface 12 +
  rdp_connections 14 + rdp_input 2).
- Test mới: seed kết nối mặc định `ace`; seed kế thừa user/pass bước 21;
  thêm kết nối (bản ghi vào prefs, mật khẩu chỉ trong secure storage —
  prefs JSON không chứa mật khẩu/username); sửa kết nối; xóa kết nối (xóa cả
  key secure storage); `saveCredentials`; cài đặt trackpad/bàn phím/favorite
  round-trip + Favorite xếp lên đầu; bấm vào card kết nối → gọi `connect`
  đúng host/port/username/password đã lưu; trang thêm lưu thành card mới (kèm
  bật Trackpad); long-press hiện menu Connect/Favorite/Edit/Delete; Edit qua
  menu lưu đúng tên + bật Trackpad; Delete qua menu sau xác nhận; Favorite
  ghim lên đầu + sao vàng, bỏ yêu thích thì hết sao; Back từ trang remote →
  ngắt kết nối (`disconnect`) + về Home; mở kết nối có trackpad + ẩn bàn
  phím → áp đúng cài đặt (bàn phím biến mất, remote full màn hình); màn hình
  remote khi đã kết nối không còn nút nào.
- Lưu ý test: sau khi bấm vào card, route mới cần 2 frame mới hiện trong cây
  widget; dialog thêm/sửa cũ đã đổi thành trang đầy đủ (đóng dialog rồi
  dispose controller ngay làm TextField trong animation thoát dùng controller
  đã dispose → lỗi); `pageBack()` đòi nút back trên AppBar (trang remote
  không có AppBar) nên test Back dùng `tester.binding.handlePopRoute()`;
  đặt `keyboardVisible` trong `initState` của pane gây lỗi
  "markNeedsBuild during build" nên phải áp dụng qua
  `addPostFrameCallback`; test mở kết nối có auto-connect phải pump qua
  delay 400 ms trước khi dispose, không thì còn timer pending.
- Kotlin/Gradle chỉ biên dịch được trên CI (không build APK trên VM).

## Cách test trên Fold6

1. Mở app: Home hiện danh sách "Kết nối đã lưu" với 1 card `ace — Windows`
   (`100.101.127.41:3389`, user `steve` nếu đã lưu ở bản trước). Bấm vào
   card → app tự kết nối luôn (không nhập lại).
2. Bấm "+" → thêm kết nối mới (tên/host/port/user/pass + công tắc Trackpad /
   Hiện bàn phím) → card mới hiện; bấm vào card mới để nối.
3. Chọn giữ (long-press) một card → menu Connect / Favorite / Edit / Delete
   hiện; bấm Edit → chỉnh tên/host/port/user/pass + Trackpad/bàn phím → Lưu
   → về Home → bấm vào card để vào lại với cài đặt mới. Bấm Favorite → card
   có sao vàng, nhảy lên đầu danh sách. Bấm Delete → hỏi xác nhận rồi xóa.
4. Trackpad: bật "Chế độ Trackpad" trong Edit của kết nối, vào lại, lướt
   ngón tay TRÊN các phím — phím vẫn hiện, con trỏ di theo; chạm nhanh vào
   phím vẫn gõ phím đó; 2 ngón chạm → click phải.
5. Con trỏ: di chuột bằng trackpad hoặc chạm — con trỏ (hình Windows hoặc
   mũi tên trắng) hiện rõ trên màn hình remote.
6. Màn hình remote: KHÔNG còn nút nào vướng tầm nhìn — không Trackpad, không
   Ẩn bàn phím, không Ngắt kết nối, không chevron. Thoát: bấm Back / vuốt
   back → ngắt kết nối, về màn hình chính (không thoát hẳn app).
7. Kết nối chậm: mở lại app, bấm kết nối, xem dòng chữ phase
   ("Đang tạo phiên…" / "Đang xác thực…" / "Đang kết nối…") và nút "Ngắt"
   bấm được để hủy. Muốn biết bước nào chậm: xem logcat tag `AceRdp`
   (thời gian từng bước: tạo session / NLA / frame đầu).
