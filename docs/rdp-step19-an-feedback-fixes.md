# Bước 19 — Sửa 4 ý An phản hồi sau khi test bản RDP (run #6) trên Fold6

## Bối cảnh
- An cài bản run #6 từ link trực tiếp, app mở được, kết nối RDP được tới màn hình khóa
  Windows (lock screen hiện, gõ được username `steve`), nhưng gặp 4 vấn đề:
  1. Kết nối được ~1 giây rồi tự ngắt (lỗi DISP).
  2. Màn hình remote chưa full viền nửa trên (còn viền đen letterbox).
  3. Phải nhập lại mật khẩu mỗi lần kết nối.
  4. 2 nút "Click trái" / "Click phải" ở cuối bàn phím quá to, mất cân đối.
- Branch: `rdp-prototype`. CI run #7 (bước 17 Firebase) chạy song song, không đụng tới —
  bản sửa này đi run #8.

## 1. DISP thất bại KHÔNG bao giờ ngắt phiên
**File:** `android/app/src/main/kotlin/vn/aceremote/app/RdpPlugin.kt`

- Xóa đường `resizeUnavailable() → stop()`. Khi DISP thất bại, phiên đang chạy tốt ở độ
  phân giải hiện tại cứ giữ nguyên; chỉ đặt cờ `resizeFailure` với thông báo
  "DISP không đổi được độ phân giải; tiếp tục dùng kích thước hiện tại.", ghi
  `Log.w("AceRdp", ...)` và đẩy snapshot mới (kèm `resizeFailure`) về Dart qua
  `change(state, error)` — state KHÔNG đổi thành `failed`.
- `finish()` không còn đổi state thành `failed` khi có `resizeFailure`.
- Không gửi DISP trong 2 giây đầu sau khi kết nối thành công (`connectedAt` ghi lúc
  `OnConnectionSuccess`; `resize()` hoãn lại tới khi hết 2 giây) — lúc đó layout và
  bàn phím mềm Android còn đang ổn định.
- Retry tối đa 3 lần (trước đây 10 lần), cách nhau 1 giây (trước đây 500 ms), sau đó thôi.
- Xoay màn hình / gập-mở Fold làm SurfaceView đổi kích thước thật vẫn thử DISP như cũ
  (không fatal).
- Lưu ý: thông báo DISP thất bại hiện CHỈ ghi log Android (`Log.w`) và nằm trong
  snapshot `resizeFailure` gửi về Dart; chưa hiện toast/snackbar trên UI (brief cho
  phép chỉ ghi log). Nếu An muốn thấy thông báo trên màn hình thì làm thêm bước sau.

## 2. Màn hình remote full viền nửa trên
**File:** `lib/rdp_surface.dart` (phần còn lại của layout đã đúng, giữ nguyên)

- `RdpConnectionPane.connect()`: ẩn bàn phím mềm trước (`FocusScope.of(context).unfocus()`),
  chờ layout ổn định 400 ms rồi mới gọi `controller.connect(...)`, để Kotlin `start()`
  đọc được đúng kích thước SurfaceView cuối cùng (trước đây lấy kích thước lúc bàn phím
  mềm còn hiện nên nhỏ hơn, sinh ra letterbox).
- Layout 50/50 ở `main.dart` đã đúng (hai `Expanded` không padding/margin, header
  "Đã kết nối / Ngắt kết nối" là overlay topRight) nên giữ nguyên.
- Giữ nguyên cách vẽ aspect-fit (letterbox) làm fallback an toàn — không đổi sang
  aspect-fill (cắt hình).

## 3. Lưu mật khẩu đã mã hóa, tự điền sẵn, có "Quên mật khẩu"
**File mới:** `lib/rdp_credentials.dart`
**File đổi:** `lib/rdp_surface.dart`, `lib/main.dart` (chỉ chuyển import/storage dùng chung)

- Dùng `flutter_secure_storage` (đã có dependency `^9.2.2` trong `pubspec.yaml`, đã dùng
  cho PIN nên không cần thêm gì). Mật khẩu RDP lưu với key `rdp_password`, dùng
  `AndroidOptions(encryptedSharedPreferences: true, sharedPreferencesName: 'ace_rdp_credentials')`
  — file preferences riêng, tách khỏi PIN. KHÔNG lưu plaintext ở đâu.
- Chỉ lưu khi kết nối thành công thật (sự kiện `connected` từ native qua
  `connectionChanged`); kết nối thất bại thì KHÔNG lưu (`pendingPassword` bị xóa).
- Lần mở app sau, `restorePassword()` tự điền sẵn vào ô Password (vẫn `obscureText`).
- Nút "Quên mật khẩu" (TextButton dưới ô Password): xóa mật khẩu đã lưu khỏi secure
  storage và trống ô Password.
- Thêm: khi ngắt kết nối hoặc kết nối thất bại, form hiện lại thì mật khẩu đã lưu được
  điền lại sẵn (không bắt nhập lại để kết nối lại). `restorePassword()` vẫn tôn trọng
  cờ `passwordEdited` — nếu người dùng đã gõ tay thì không ghi đè.
- Mật khẩu vẫn chỉ tồn tại trong RAM lúc kết nối (Kotlin `clearCredentials()` giữ nguyên).

## 4. Bỏ 2 nút Click trái/phải; chạm 2 ngón đứng yên = click phải
**File đổi:** `lib/main.dart`, `android/app/src/main/kotlin/vn/aceremote/app/RdpPlugin.kt`

- Xóa hàng 6 (`row(6, [laptopKey('Click trái'), laptopKey('Click phải')], flex: 2)`)
  khỏi bàn phím ở chế độ RDP; xóa nhánh xử lý riêng cho 2 nút đó trong `press()` ở
  RDP mode (mọi phím giờ đi qua `rdpKey`). Bàn phím RDP còn 6 hàng (0–5).
  Chế độ agent v1.4 giữ nguyên 2 nút (không đụng agent-mode).
- Mapping chạm mới (Kotlin `onTouch`):
  - Chạm nhanh 1 ngón (<12 px, <500 ms) = click trái (đã có).
  - Kéo 1 ngón = di chuột + giữ trái (drag) (đã có).
  - Long-press 500 ms = click phải (đã có).
  - **MỚI: chạm 2 ngón đứng yên = click phải tại điểm giữa 2 ngón.** Theo dõi tổng
    quãng di chuyển của điểm giữa 2 ngón (`twoFingerTravel`) + `scrollAccum`; chỉ
    click phải khi cả hai <48 px lúc nhấc ngón lên và thời gian <500 ms. Nếu đã cuộn
    (di chuyển ≥48 px) thì không click.
  - Kéo 2 ngón = cuộn (đã có).
  - Chạm vào vùng đen letterbox vẫn bỏ qua (đã có; nay kiểm tra cả ngón thứ 2: nếu
    một trong hai ngón nằm trong vùng đen thì hủy toàn bộ cử chỉ).

## Kiểm chứng trên VM (Flutter 3.50.0)
- `flutter analyze`: **0 issue**.
- `flutter test`: **38/38 pass** (35 cũ + 3 mới: khôi phục mật khẩu đã lưu + quên mật
  khẩu; chỉ lưu mật khẩu sau khi native báo connected; điền lại mật khẩu sau khi ngắt
  kết nối). Test RDP keyboard cũ đã cập nhật: không còn tìm thấy 'Click trái' /
  'Click phải' và `keyboard-row-6` ở chế độ RDP.
- Kotlin (DISP + chạm 2 ngón) không kiểm chứng được trên VM — chỉ compile được trên CI.
- Lưu ý quy trình: phiên Codex CLI chạy bước này gặp lỗi sandbox (SDK cache chỉ đọc
  trong sandbox của nó; nó copy SDK sang /tmp làm đầy /tmp 512M nên phiên dừng giữa
  chừng với exit 101, chưa kịp chạy analyze/test và chưa viết doc). Đã dọn /tmp và
  kiểm chứng analyze/test trực tiếp trên VM; phần code chính của Codex giữ nguyên,
  chỉ thêm phần điền lại mật khẩu sau khi ngắt kết nối + test tương ứng + doc này.

## Cách test trên Fold6
1. **Không tự ngắt (việc 1):** cài bản mới, kết nối, đợi >10 giây — xác nhận không tự
   ngắt, không bắt nhập lại mật khẩu. Xoay màn hình / gập-mở Fold — xác nhận không
   tự ngắt. (Nếu server ở màn hình khóa không áp dụng DISP thì phiên vẫn chạy ở độ
   phân giải cũ; kiểm tra logcat có dòng `AceRdp` với thông báo DISP nếu muốn.)
2. **Full viền (việc 2):** sau khi kết nối, ảnh remote lấp đầy nửa trên, không còn
   viền đen lớn. Gõ username/password ở màn hình khóa, đăng nhập, xem desktop có
   lấp đầy không.
3. **Lưu mật khẩu (việc 3):** kết nối 1 lần thành công, thoát app hẳn, mở lại — ô
   Password đã điền sẵn (dạng •••). Bấm "Quên mật khẩu" → ô trống lại; kết nối lại
   phải nhập tay. Ngắt kết nối rồi kết nối lại ngay — ô Password đã điền sẵn lại.
4. **Chạm (việc 4):** bàn phím chỉ còn 6 hàng, không còn 2 nút Click to ở cuối.
   Chạm 1 ngón lên màn hình remote = click trái (bấm được icon/nút trên desktop).
   Chạm 2 ngón đứng yên rồi nhấc lên = click phải (hiện menu ngữ cảnh). Kéo 2 ngón
   = cuộn. Long-press 1 ngón vẫn = click phải.
