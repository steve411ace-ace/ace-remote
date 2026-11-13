# Bước 21 — Lưu username + bỏ "Quên mật khẩu" + header tự ẩn + chế độ Trackpad + ẩn/hiện bàn phím

## Bối cảnh
- An test bản bước 19 (run #8) trên Fold6 lúc 02:36–02:46 và báo thêm:
  1. Lưu mật khẩu nhưng KHÔNG lưu username — mở app lại thì ô Password đã điền sẵn
     nhưng ô Username trống, phải gõ lại.
  2. Bỏ nút "Quên mật khẩu" dưới ô Password.
  3. Màn hình remote còn dải đen ở dưới nửa trên + 2 nút "Đã kết nối / Ngắt kết nối"
     đè lên góc trên-phải màn hình remote (An xác nhận đúng 2 chỗ).
  4. "Anh không thao tác di chuột trên bàn phím được" — sau đó An làm rõ: thao tác
     chạm trên màn hình remote đã OK, nhưng anh muốn THÊM chế độ trackpad (di chuột
     tương đối) ở cả hai nửa.
  5. "Sẵn làm nút chế độ chạm/trackpad này, e làm thêm ẩn hiện bàn phím luôn em. Để
     nếu anh có dùng phím rời thì dùng full màn hình."
- An đính chính lúc 02:43: **dải đen KHÔNG phải lỗi** — "Chỗ đó là thanh taskbar đó
  do chưa load đủ" (vùng taskbar của Windows chưa render kịp, không phải letterbox;
  màn hình remote thực ra đã lấp đầy nửa trên). → Việc sửa full viền ĐÃ BỎ khỏi
  bước này, không sửa gì thêm (xem mục 3).
- Branch: `rdp-prototype`. Base là commit `16477f1` (bước 20: fixed key code + bỏ
  PIN, CHƯA push). Bản này đi run #9 CÙNG với bỏ PIN (push chọn lọc: chỉ các file
  bước 21 + bỏ PIN, KHÔNG push file fixed key vì secret chưa có — workflow fixed
  key sẽ FAIL nếu push khi chưa có secret).

## 1. Lưu username (giống như đã lưu mật khẩu)
**File:** `lib/rdp_credentials.dart` (thêm key), `lib/rdp_surface.dart`

- Thêm key `rdp_username` vào cùng secure storage với mật khẩu (cùng file
  `ace_rdp_credentials`, `encryptedSharedPreferences=true`). Không lưu plaintext.
- Lưu khi nào: khi kết nối thành công (cùng lúc với lưu mật khẩu — chỉ lưu khi
  native báo `connected`, qua `pendingUsername` giống `pendingPassword`). Thất bại
  thì không lưu.
- Lần mở app sau: `restoreCredentials()` (đổi tên từ `restorePassword()`) tự điền
  sẵn cả Username và Password. Khi ngắt/thất bại thì form hiện lại vẫn điền sẵn
  cả hai (mở rộng cơ chế điền lại sau ngắt kết nối ở bước 19).
- Username tôn trọng cờ `usernameEdited` (mới, giống `passwordEdited`): nếu người
  dùng đã gõ tay thì `restoreCredentials()` không ghi đè. `connect()` đặt cả hai
  cờ thành true trước khi gửi; khi failed/disconnected thì reset cả hai về false
  rồi điền lại từ storage.
- Lưu ý: ô Username KHÔNG bị xóa khi bấm Kết nối (chỉ ô Password bị xóa trong
  `finally` vì lý do bảo mật), nên username người dùng vừa gõ vẫn còn đó khi form
  hiện lại; `restoreCredentials()` điền lại giá trị đã lưu (là username của lần
  kết nối thành công gần nhất).

## 2. Bỏ nút "Quên mật khẩu"
**File:** `lib/rdp_surface.dart`, `test/rdp_surface_test.dart`

- Xóa nút TextButton "Quên mật khẩu" dưới ô Password và xóa luôn hàm
  `forgetPassword()` (chỉ nút này dùng, đã kiểm tra bằng grep — không còn chỗ nào
  gọi nữa).
- Hệ quả: mật khẩu đã lưu sẽ ở lại trong secure storage cho tới khi xóa dữ liệu
  app / gỡ app. Đây là ý An (anh không muốn nút này). Muốn đổi mật khẩu đã lưu thì
  chỉ cần gõ mật khẩu mới rồi kết nối thành công một lần — giá trị mới sẽ ghi đè
  giá trị cũ.
- Test "quên mật khẩu" cũ đã gỡ; test khôi phục đã cập nhật để khẳng định nút
  "Quên mật khẩu" không còn xuất hiện (`findsNothing`).

## 3. Dải đen ở dưới nửa trên — KHÔNG PHẢI LỖI, KHÔNG SỬA
- An đính chính 02:43: dải đen là vùng thanh taskbar của Windows chưa kịp load
  xong (chưa render), không phải letterbox do sai độ phân giải. Màn hình remote
  thực ra đã lấp đầy nửa trên đúng rồi.
- Vì vậy KHÔNG điều tra/sửa full viền trong bước này, KHÔNG thêm log debug kích
  thước. Cơ chế DISP/resize ở bước 19 giữ nguyên. Nếu sau này An thấy viền đen
  thật sự (ảnh remote không lấp đầy mà taskbar đã load xong) thì điều tra riêng.

## 4. Header "Đã kết nối / Ngắt kết nối" tự ẩn sau 3 giây
**File:** `lib/rdp_surface.dart`

- Khi đã kết nối, header (Chip "Đã kết nối" + các nút) hiện ra rồi **tự ẩn sau
  3 giây** (`Timer` trong `showHeaderTemporarily()`, khởi động khi native báo
  `connected` qua `connectionChanged`). Khi header ẩn, chỉ còn một nút tròn nhỏ
  mờ (icon `expand_more`, tooltip "Hiện điều khiển") ở góc trên-phải — bấm vào
  thì header hiện lại trong 3 giây.
- Bấm bất kỳ nút nào trên header (chuyển chế độ, ẩn/hiện bàn phím) cũng khởi động
  lại bộ đếm 3 giây, nên header không biến mất giữa chừng lúc đang bấm.
- Khi ngắt kết nối / thất bại thì timer bị hủy và header reset về hiện (để lần
  kết nối sau lại hiện như cũ). Timer hủy trong `dispose()`.
- Header KHÔNG thành hàng layout cố định (không chiếm chỗ, nửa trên vẫn full
  viền như cũ).

## 5. Chế độ Trackpad (di chuột tương đối) — nút "Trackpad / Chạm" trên header
**File:** `lib/rdp_surface.dart`, `lib/main.dart`,
`android/app/src/main/kotlin/vn/aceremote/app/RdpPlugin.kt`

### Công tắc và trạng thái
- Nút `Trackpad` / `Chạm` nằm trên header (cùng hàng với "Đã kết nối" và "Ngắt
  kết nối"), chỉ hiện khi đã kết nối. Bấm để đổi chế độ; nhãn nút hiện chế độ
  sẽ chuyển tới (đang ở Chạm thì nút ghi "Trackpad", đang ở Trackpad thì nút ghi
  "Chạm").
- Trạng thái nằm ở `RdpController` (`trackpadMode`, `ValueNotifier<bool>`, mặc
  định `false` = Chạm) — một nguồn duy nhất cho cả header, nửa dưới, và native.
  `setTrackpadMode()` gửi lệnh `'mode'` qua MethodChannel xuống native; `attach()`
  gửi lại chế độ hiện tại để đề phòng trường hợp đổi chế độ trước khi view gắn.
- Chuyển chế độ KHÔNG làm mất kết nối RDP, KHÔNG reset con trỏ (native chỉ đổi
  cách diễn giải cử chỉ; `lastX/lastY` giữ nguyên, bộ tích lũy float được đồng bộ
  lại từ vị trí con trỏ hiện tại).

### Chế độ "Chạm" (mặc định, giữ nguyên như cũ)
- Nửa trên (màn hình remote): chạm tuyệt đối — chạm = nhảy tới điểm đó + click
  trái, kéo = di chuột + giữ nút trái (drag), long-press 500 ms = click phải,
  kéo 2 ngón = cuộn, chạm 2 ngón đứng yên = click phải tại điểm giữa.
- Nửa dưới: bàn phím laptop gõ chữ (6 hàng, như bước 19).

### Chế độ "Trackpad" (mới)
- **Nửa trên (màn hình remote)** — native `onTouchTrackpad()` trong
  `RdpPlugin.kt` (đường chạm riêng, gọi từ `onTouch()` khi `trackpadMode` bật):
  - Kéo 1 ngón = di chuột tương đối (chỉ di con trỏ, KHÔNG giữ nút, KHÔNG nhảy
    tới điểm chạm). Con trỏ di theo hướng và tỉ lệ với quãng kéo, hệ số nhạy
    **1.5x** (`TRACKPAD_SENSITIVITY = 1.5f`): kéo 100 px trên màn hình thì con trỏ
    di ~150 px trên framebuffer — đủ nhanh để đi hết màn hình bằng một lần kéo
    ngắn, đủ chậm để ngắm chính xác. Dùng bộ tích lũy float
    (`trackpadCursorX/Y`) để không bị mất phần lẻ khi làm tròn từng sự kiện
    (tránh con trỏ "giật" khi kéo chậm).
  - Chạm nhanh 1 ngón (<12 px, <500 ms) = click trái **tại vị trí con trỏ hiện
    tại** (không nhảy tới điểm chạm).
  - Long-press 500 ms = click phải (giữ như chế độ Chạm).
  - Chạm 2 ngón đứng yên = click phải tại vị trí con trỏ (không phải tại điểm
    giữa 2 ngón như chế độ Chạm).
  - Kéo 2 ngón = cuộn (giống chế độ Chạm, 1 notch mỗi 48 px).
  - Chạm trong vùng đen letterbox (nếu có) vẫn có tác dụng — toàn bộ mặt
    SurfaceView là trackpad nên không kiểm tra biên như chế độ Chạm.
- **Nửa dưới (mặt trackpad)** — thay bàn phím bằng widget `RdpTrackpad` mới
  trong `lib/main.dart` (mặt tối có chữ gợi ý mờ "Trackpad — Kéo để di chuột •
  Chạm để click trái • 2 ngón: click phải • kéo để cuộn"):
  - Kéo 1 ngón = di chuột tương đối (gửi `moveRelative` với delta theo pixel
    vật lý = pixel logic × devicePixelRatio; native đổi sang pixel framebuffer
    với cùng hệ số nhạy 1.5x và cùng bộ tích lũy float — chung hàm
    `moveCursorRelative()` với nửa trên).
  - Chạm nhanh = click trái tại con trỏ (`clickAtLastPosition('left')`).
  - Chạm 2 ngón đứng yên = click phải (`clickAtLastPosition('right')`).
  - Kéo 2 ngón = cuộn, 1 notch mỗi 48 px logic (`scrollWheel(down)`).
  - KHÔNG có long-press ở mặt trackpad dưới (chạm 2 ngón đã là click phải;
    tránh click phải vô tình khi đặt tay nghỉ).
  - Các lệnh gửi đi là fire-and-forget (`unawaited`); native tự gộp (coalesce)
    các sự kiện MOVE liên tiếp nên kéo nhanh không bị tắc nghẽn.
- MethodChannel mới (native `RdpView`):
  - `'mode'` `{'trackpad': bool}` — bật/tắt chế độ trackpad ở nửa trên; đổi chế
    độ thì hủy cử chỉ đang dở (`resetTouch()`).
  - `'moveRelative'` `{'dx': double, 'dy': double}` — delta theo pixel vật lý
    của mặt SurfaceView; native đổi sang pixel framebuffer.
  - `'scroll'` `{'down': bool}` — một notch wheel tại vị trí con trỏ hiện tại.

## 6. Nút ẩn/hiện bàn phím (dùng full màn hình khi có phím rời)
**File:** `lib/rdp_surface.dart`, `lib/main.dart`

- Nút `Ẩn bàn phím` / `Hiện bàn phím` nằm trên header, ngay cạnh nút
  "Trackpad / Chạm" (cùng khu vực điều khiển, dễ bấm). Nhãn hiện hành động sẽ
  làm (đang hiện thì nút ghi "Ẩn bàn phím", đang ẩn thì ghi "Hiện bàn phím").
- Bấm **Ẩn bàn phím**: nửa dưới (bàn phím hoặc trackpad) biến mất, màn hình
  remote (nửa trên) mở rộng ra lấp đầy **toàn bộ** chiều cao RemotePage (100%).
  Bấm **Hiện bàn phím**: quay về chia 50/50 như cũ.
- Nút này nằm ở header trên màn hình remote nên **vẫn bấm được khi bàn phím
  đang ẩn** (không giấu nút vào trong vùng bàn phím). Nếu header đang tự ẩn thì
  bấm nút tròn "Hiện điều khiển" ở góc trên-phải để hiện header lên rồi bấm.
- Trạng thái nằm ở `RdpController` (`keyboardVisible`, `ValueNotifier<bool>`,
  mặc định `true`); layout RDP ở `RemotePage` theo dõi qua
  `ValueListenableBuilder` và chỉ render nửa dưới khi `kbVisible == true`.
  Chuyển đổi không làm mất kết nối, không reset con trỏ.
- **Đổi độ phân giải khi ẩn/hiện:** khi nửa dưới biến mất, SurfaceView to ra
  (gấp đôi chiều cao) → `surfaceChanged` bắn → cơ chế resize/DISP đã có từ bước
  19 tự gửi độ phân giải mới lên server. **Hạn chế đã biết:** nếu server không
  áp dụng DISP (DISP thất bại) thì phiên vẫn giữ kết nối bình thường (như bước
  19 — không ngắt phiên, chỉ ghi log `Log.w("AceRdp", ...)`), nhưng ảnh remote
  sẽ ở độ phân giải cũ và letterbox trong vùng to hơn (viền đen). Khi đó bấm
  hiện bàn phím để quay về 50/50 là ảnh lại vừa. Cần test thật trên Fold6 để
  biết server có áp dụng DISP khi đổi kích thước lớn như vậy không.
- **Tương tác với chế độ Trackpad:** khi bàn phím đang ẩn thì trackpad ở nửa
  dưới không còn ý nghĩa (nửa dưới đã biến mất), nhưng chế độ Trackpad ở nửa
  trên (màn hình remote) vẫn hoạt động bình thường (kéo = di chuột tương đối).
  Khi hiện lại bàn phím thì quay về đúng chế độ đang chọn (Chạm hoặc Trackpad)
  như trước — chế độ không bị reset khi ẩn/hiện bàn phím. Nút "Trackpad / Chạm"
  vẫn bấm được khi bàn phím đang ẩn (nó nằm trên header).

## Kiểm chứng trên VM (Flutter 3.50.0)
- `flutter analyze`: **0 issue**.
- `flutter test`: **41/41 pass** (38 cũ + 3 mới: header tự ẩn + chuyển chế độ +
  trackpad dưới; ẩn/hiện bàn phím. Test cũ cập nhật: khôi phục username +
  password, bỏ test quên mật khẩu, chỉ lưu sau khi connected cho cả username).
  Hai test cũ phải sửa theo code mới: test bàn phím VK (`attach()` giờ gửi thêm
  lệnh `'mode'` nên phải `calls.clear()` sau attach) và test điền lại sau ngắt
  kết nối (username đã lưu sau lần kết nối thành công là `'user'` đã gõ, không
  còn là `'saved-user'` ban đầu — đúng hành vi lưu khi connected).
- Kotlin (chế độ trackpad native + 3 method channel mới) chưa kiểm chứng được
  trên VM — chỉ compile được trên CI (run #9).
- Không đụng file fixed key (`build.gradle`, 2 workflow), không đụng
  `proguard-rules.pro`, không khôi phục PIN. Không commit/push.

## Cách test trên Fold6
1. **Lưu username:** kết nối 1 lần thành công với username `steve`, thoát app hẳn,
   mở lại — cả ô Username và ô Password đều đã điền sẵn. Ngắt kết nối rồi kết nối
   lại ngay — cả hai ô vẫn điền sẵn. (Không còn nút "Quên mật khẩu" dưới ô
   Password; muốn đổi mật khẩu đã lưu thì gõ mật khẩu mới rồi kết nối thành công
   một lần.)
2. **Header tự ẩn:** kết nối, đợi 3 giây — header (Đã kết nối + các nút) tự biến
   mất, màn hình remote không còn bị che. Bấm nút tròn nhỏ ở góc trên-phải —
   header hiện lại. Bấm "Ngắt kết nối" vẫn được khi header đang hiện.
3. **Chế độ Trackpad:** kết nối, bấm nút "Trackpad" trên header — nửa dưới thành
   mặt trackpad (nền tối, có chữ gợi ý mờ). Kéo trên mặt trackpad: con trỏ trên
   màn hình remote di theo hướng kéo (không nhảy tới điểm chạm, không giữ nút).
   Chạm nhanh trên mặt trackpad: click trái tại vị trí con trỏ. Chạm 2 ngón
   đứng yên: click phải. Kéo 2 ngón: cuộn. Trên nửa trên cũng vậy: kéo để di
   chuột tương đối, chạm nhanh để click trái tại con trỏ. Bấm nút "Chạm" để về
   chế độ cũ (chạm tuyệt đối + bàn phím). Kiểm tra: chuyển chế độ không ngắt
   kết nối, con trỏ không nhảy về giữa màn hình.
4. **Ẩn/hiện bàn phím:** kết nối, bấm "Ẩn bàn phím" — bàn phím biến mất, màn
   hình remote mở rộng lấp đầy toàn bộ màn hình. Dùng phím rời (nếu có) để gõ.
   Bấm "Hiện bàn phím" (trên header; nếu header đang ẩn thì bấm nút tròn góc
   trên-phải trước) — quay về 50/50. Lưu ý: khi ẩn bàn phím, nếu ảnh remote bị
   viền đen (letterbox) thì là do server không áp dụng DISP cho kích thước mới —
   phiên vẫn chạy bình thường, chỉ ghi log; báo lại để xử lý tiếp.
5. **Kết hợp:** bật chế độ Trackpad rồi ẩn bàn phím — nửa trên vẫn di chuột
   tương đối được. Hiện lại bàn phím — vẫn ở chế độ Trackpad (không bị reset về
   Chạm).
