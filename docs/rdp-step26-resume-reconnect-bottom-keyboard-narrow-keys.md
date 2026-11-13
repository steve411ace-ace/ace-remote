# Bước 26 — Tự nối lại khi mở lại từ đa nhiệm, bàn phím sát mép dưới, phím hẹp khi gập

An test bản run #13 (bước 25) trên Fold6, 06:15 ngày 14/11/2026. Bước 26
ban đầu có 4 việc; An bỏ việc 2 lúc 06:17 ("Khỏi chỉnh phím lùn lại đi em
như vầy oke rồi") và thêm việc 4 lúc 06:19. Còn lại 3 việc đang làm: 1, 3, 4.

## Việc 1 — Sửa DỨT ĐIỂM kẹt "Đang kết nối..." khi mở lại từ đa nhiệm

### Triệu chứng
Kết nối RDP đang chạy → bấm recents → mở app khác một lúc → quay lại Ace
Remote từ đa nhiệm → thẻ "Đang kết nối..." (kiểu mới, bước 24) hiện kẹt
hoài, không tự nối lại được; phải bấm Back ra vào lại mới được. Bước 25 đã
làm 2 lớp phòng thủ (`_resumeRdp()` re-query trạng thái + watchdog 30 giây)
nhưng trên máy thật vẫn kẹt.

### Nguyên nhân ĐÚNG (đã chứng minh từ source, không đoán)
Đọc `~/workspace/FreeRDP-3.33.0` (tag 3.33.0, cùng source CI build AAR)
và code app, có 3 lỗi thiết kế chồng lên nhau:

1. **Watchdog bước 25 không bao giờ nổ trong vòng lặp nối lại.**
   `client_auto_reconnect_do` (`client/common/client.c`) lặp tối đa
   `AutoReconnectMaxRetries = 20` lần (mặc định, `settings.c:1266`).
   Mỗi lần lặp gọi RetryDialog (`android_retry_dialog`,
   `android_freerdp.c`) → `OnReconnecting` → Dart nhận event
   `'connecting'` mới, rồi `freerdp_reconnect()`; thất bại thì ngủ
   delay rồi lặp lại. Mỗi lần lặp còn đi qua `OnPreConnect` /
   `OnAuthenticate` — cũng là event `'connecting'` mới. Mỗi event là
   một Map mới → `ValueNotifier` notify → `connectionChanged()` của
   bước 25 **vũ trang lại timer 30 giây**. Vòng lặp cứ đổi phase liên
   tục nên timer không bao giờ chạm mốc 30 giây. Ngoài ra
   `_resumeRdp()` gán lại `controller.value` cũng kích hoạt listener
   (một lần vũ trang lại nữa). Đây là lỗi chính.
   - Ghi chú: `android_retry_dialog` có chờ `foregroundEvent` với
     `INFINITE`, nhưng app mình KHÔNG BAO GIỜ gọi
     `LibFreeRDP.setForeground()` (chỉ `SessionActivity.java` của
     aFreeRDP gọi) nên event này ở trạng thái signaled ban đầu và
     không chặn vòng lặp trong app mình.
   - Mỗi lần lặp tốn tối đa ~15s (`TcpConnectTimeout` mặc định 15000ms,
     `settings.c:1322`) + delay ≤ 3s → 20 lần có thể kéo dài nhiều phút.

2. **`_resumeRdp()` chỉ re-query trạng thái, không nối lại thật.**
   Nó gán `rdpController.value = status` rồi thôi. Native đang kẹt
   trong vòng lặp thì Dart chỉ nhận lại `'connecting'`. Và dù Dart có
   muốn nối mới cũng không được: handler `'connect'` của native từ
   chối khi `attempt != null` ("Phiên trước chưa kết thúc").

3. **Ép `'failed'` cũng bị ghi đè.** `_onBusyTimeout` ép state Dart
   thành `'failed'`, nhưng event `'connecting'` tiếp theo từ vòng lặp
   native sẽ ghi đè lại thành `'connecting'` → spinner quay lại.

### Cách sửa (`lib/rdp_surface.dart`, chỉ phía Dart, không đụng native)
- **Watchdog có deadline TUYỆT ĐỐI:** thêm `_busySince` — đặt 1 lần khi
  episode bận BẮT ĐẦU, `_busyWatchdog ??=` một timer duy nhất. Đổi
  phase hay re-query trạng thái đều không dời deadline. Sau 30s tuyệt
  đối mà vẫn bận → `_onBusyTimeout()` hủy phiên + ép `'failed'` như cũ.
  `_onBusyTimeout` xóa `_busySince`/`_busyWatchdog` để episode bận sau
  vũ trang timer mới.
- **Pane tự nối lại thật khi resume:** `_RdpConnectionPaneState` giờ là
  `WidgetsBindingObserver`; `didChangeAppLifecycleState(resumed)` gọi
  `_resumeReconnect()`:
  - Phiên vẫn `'connected'` → không làm gì (không nối lại thừa).
  - Chưa từng nối hoặc user đã bấm "Ngắt" → không làm gì (cờ
    `_resumeReconnectArmed`, bật khi state thành `'connected'`, tắt
    khi user bấm "Ngắt" qua `_cancelConnect()` mới; watchdog gọi
    `disconnect()` trực tiếp nên KHÔNG tắt cờ).
  - Đang `'connecting'`/`'disconnecting'` → `disconnect()` hủy phiên cũ
    (native `stop()` → `cancelConnection` = `freerdp_disconnect`, đặt
    lỗi `FREERDP_ERROR_CONNECT_CANCELLED` + abort connect đang chạy),
    rồi poll `status()` mỗi 200ms tối đa ~5s chờ native dọn xong
    (`attempt` về null), rồi nạp lại user/pass đã lưu và `connect()`
    một lần. Thất bại thì dừng ở form với nút "Kết nối lại" (không lặp).
  - Đã `'failed'`/`'disconnected'` (vòng lặp hết 20 lần khi đang ở nền)
    → bỏ qua bước hủy, nạp lại user/pass rồi `connect()` luôn.
  - Cờ `_resumeReconnectRunning` chặn 2 lần resume (hoặc resume đua với
    watchdog) chạy chồng nhau.
- `_RemotePageState._resumeRdp()` giữ nguyên (re-query để đồng bộ state);
  pane làm phần nối lại thật. Nút "Ngắt" giờ gọi `_cancelConnect()`
  (tắt cờ + disconnect) thay vì `disconnect()` trực tiếp.

### Test mới (test/rdp_surface_test.dart)
- `repeated connecting events do not postpone the watchdog` — gửi event
  `'connecting'` mới mỗi 10s (mô phỏng vòng lặp nối lại); watchdog vẫn
  nổ đúng 30s tuyệt đối (test này FAIL trên code bước 25).
- `resuming from background auto-reconnects a stuck session` — nối thành
  công 1 lần (bật cờ), rồi kẹt `'connecting'`, pause → resume → pane
  gửi `'disconnect'` hủy phiên cũ rồi `'connect'` mới đúng 1 lần với
  user/pass đã lưu trong secure storage mock.
- Test resume cũ của bước 25 giữ nguyên (native đã `'idle'` thì chỉ
  re-sync, không nối lại — vì chưa từng nối nên cờ tắt).

### Cách test trên Fold6
1. Kết nối RDP → bấm recents → mở app khác một lúc → quay lại Ace Remote
   từ đa nhiệm → desktop tự hiện lại, KHÔNG cần bấm Back hay "Kết nối lại".
2. Trường hợp xấu nhất (máy chủ vẫn chưa với tới được): sau tối đa 30 giây
   spinner tự biến mất, hiện form kèm user/pass đã lưu để bấm "Kết nối lại".
3. Giới hạn: không tái hiện được vòng lặp nối lại thật trên VM (cần máy thật
   + logcat). Nếu vẫn kẹt, lấy logcat tag `AceRdp` lúc mở lại từ đa nhiệm
   (sẽ thấy các dòng `connect: ...` và `busy state ... stuck >30s` nếu
   watchdog nổ).

## Việc 2 — ĐÃ BỎ theo ý An (06:17)
"Khỏi chỉnh phím lùn lại đi em như vầy oke rồi." Giữ nguyên chiều cao phím
như bước 25 (công thức `rowHeight` không đổi). Không có code cho việc này.

## Việc 3 — Bàn phím xuống sát mép dưới, màn remote to lên đến mép phím

Bỏ tỉ lệ 50/50 cố định. `lib/main.dart`:
- Thêm helper `_keyboardRowHeight(maxWidth, maxHeight)` — cùng một công thức
  bước 25, dùng chung cho cả `keyboardPanel()` và layout RDP để hai chỗ
  luôn khớp nhau.
- Nhánh RDP trong `RemotePage.build`: màn remote (`RdpConnectionPane`)
  vẫn `Expanded` (lấy toàn bộ phần còn lại phía trên); bàn phím nằm trong
  `SizedBox(height: rowHeight*6 + 8)` KHÔNG `Expanded` nữa — chiều cao cố
  định theo đúng 6 hàng phím + padding, dính sát mép dưới (là child cuối
  của Column, không còn khoảng trống dưới bàn phím).
- Độ phân giải phiên RDP theo đúng kích thước mới của SurfaceView qua logic
  DISP đã có (`surfaceChanged` → `scheduleResize` → gửi DISP; thất bại thì
  giữ kết nối, ảnh letterbox). Ẩn bàn phím vẫn cho remote lấp đầy toàn màn
  hình như cũ.
- Chế độ agent (non-RDP) không đổi (vẫn `Expanded` + căn giữa như cũ).

Số liệu (chiều cao phím giữ nguyên như bước 25):
- Màn gập Fold6 378×800: hàng phím 44 → bàn phím 272, màn remote 528
  (trước 400, +32%).
- Màn mở ~707×800: hàng phím ~50 → bàn phím ~308, màn remote ~492
  (trước 400, +23%).
- 800×600: bàn phím 347.7, màn remote 252.3.

## Việc 4 — Khi gập, thu hẹp phím rộng để phím chữ/số to lên

An (06:19): "À khi gập mấy phím shift tab cab \ ... em cho nhỏ lại để mấy
phím qwerty phím số to lên em." ("cab" = Caps.) Đây là chỉnh CHIỀU RỘNG,
khác việc 2 đã bỏ (chiều cao). `lib/main.dart`, trong `keyboardPanel()`:
- Ngưỡng hẹp: `box.maxWidth < 600` (màn gập Fold6 ~378 logical px; màn mở
  ~707+ nên giữ nguyên units bước 24/25).
- Units khi hẹp (chỉ đổi phím rộng, phím chữ/số vẫn 1 unit):
  Del 2.5→2.0, Backspace 2.0→1.5, Tab 1.5→1.0, `\` 1.5→1.0,
  Caps 1.75→1.25, Enter 2.25→1.75, Shift trái 2.25→1.5, Shift phải 2.0→1.5,
  Ctrl/Win/Alt/Left/Right 1.25→1.15, Space 4.5→4.0.
- Tổng units mỗi hàng khi hẹp: hàng F / hàng số 15.5 (= nhau, F1–F12 vẫn
  bằng phím số), các hàng còn lại 15.0, hàng dưới 15.05 (hàng 4 và 5 giữ
  bằng nhau nên ↑ vẫn bằng ↓, lệch 0.08px).
- Hiệu quả ở 378px: phím chữ 25.2px (trước 23.3px, +8%), phím số 24.4px
  (+5%), nhãn không bị cắt (FittedBox vẫn thu nhỏ nhãn dài cho vừa phím).

## Kiểm chứng
- `flutter analyze`: 0 issue.
- `flutter test`: **72/72 pass** (70 cũ + 2 mới: watchdog tuyệt đối,
  resume auto-reconnect). Test cập nhật: test "equal halves" → test bàn
  phím sát dưới + remote lấp đầy (2 cỡ màn hình); test ẩn bàn phím đổi số
  theo layout mới (remote 252.3 / bàn phím 347.7 ở 800×600); test màn
  gập/mở thêm assertion units hẹp (Tab = phím chữ, Shift = 1.5× phím chữ,
  Backspace = 1.5× phím số, ↑ = ↓ cả chiều rộng lẫn chiều cao).
- Không đụng: fixed key (`build.gradle`, 2 workflow), `proguard-rules.pro`,
  PIN, Caps Lock bước 22, lưu user/pass + danh sách kết nối bước 23, các
  phím bước 24/25 (Left/Right, PgUp/PgDn/Home/End, mũi tên T ngược, hàng F).
- Token Codex: 0 (làm trực tiếp).
