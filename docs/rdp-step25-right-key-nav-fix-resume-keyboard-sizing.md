# Bước 25 — Phím Right + sửa PgUp/PgDn/Home/End + chống kẹt "Đang kết nối..." + cỡ bàn phím màn gập + hàng F

Base: `9501659` (bước 24), branch `rdp-prototype`. An test bản run #12
(bước 24) trên Fold6 và nói "Oke đẹp rồi đó", còn 4 vấn đề; sau đó An thêm
việc 5 (cỡ hàng F). Bước 25 làm cả 5 việc, theo thứ tự An dặn (việc 4 sau
việc 1; việc 5 làm chung với việc 4).

## Việc 1: Phím "Left" bên phải Space đổi thành "Right" (chuột phải)

- Hàng dưới trước đây có 2 phím "Left" kẹp 2 bên Space, cả 2 đều click
  trái. Giờ phím bên TRÁI Space vẫn là "Left" (click trái), phím bên PHẢI
  Space là "Right" (click phải tại con trỏ).
- RDP mode: phím Right gửi `RdpController.clickAtLastPosition('right')`;
  agent mode: `click('right')` (endpoint `/click`). Dùng được cả Chạm lẫn
  Trackpad. Kích cỡ (1.25 units, bằng Alt) và màu như các phím khác.
- Nhãn 'Right' không được đi qua `rdpKey` (vì 'Right' trong
  `rdpVirtualKey` là phím mũi tên phải VK_RIGHT 0x127) — nhánh click rẽ
  trước như phím Left, trong `laptopKey.press()`.
- Nhãn 2 phím giờ khác nhau ('Left'/'Right') nên không cần `keyId` riêng
  để highlight nữa (đã bỏ `Left-1`/`Left-2`).

## Việc 2: Sửa 4 phím PgUp/PgDn/Home/End — bấm không phản hồi

### Nguyên nhân (đã kiểm chứng trong source FreeRDP 3.33.0, không đoán)

Đường đi của phím: Dart `rdpVirtualKey()` → MethodChannel `'key'`
(`RdpController.sendKey`) → `RdpPlugin.kt` `keyInput()` →
`LibFreeRDP.sendKeyEvent(handle, vk, down)` → JNI
`freerdp_send_key_event` (`android_freerdp.c`):

```c
scancode = GetVirtualScanCodeFromVirtualKeyCode(keycode, 4);
flags |= (scancode & KBDEXT) ? KBD_FLAGS_EXTENDED : 0;
event = android_event_key_new(flags, scancode & 0xFF);
```

`GetVirtualScanCodeFromVirtualKeyCode` (`winpr/libwinpr/input/scancode.c`,
type 4 = IBM_ENHANCED) rẽ nhánh theo cờ trong mã VK đầu vào:

- `vkcode & KBDEXT (0x100)` → tra bảng **mở rộng** KBD4X, trả về
  scancode | KBDEXT.
- Không có cờ → tra bảng **thường** KBD4T.

Trong bảng IBM_ENHANCED, 4 phím này CHỈ có trong bảng mở rộng
(`KBD4_X47 VK_HOME`, `KBD4_X48 VK_UP`, `KBD4_X49 VK_PRIOR`,
`KBD4_X4B VK_LEFT`, `KBD4_X4D VK_RIGHT`, `KBD4_X4F VK_END`,
`KBD4_X50 VK_DOWN`, `KBD4_X51 VK_NEXT`, `KBD4_X53 VK_DELETE`); bảng
thường tại cùng các scancode lại giữ `VK_NUMPAD7/9/1/3`
(`KBD4_T47/T49/T4F/T51`). Bước 24 gửi mã VK thuần (0x21–0x24) nên tra
bảng thường không thấy gì → scancode 0 → sự kiện phím mã 0 → server
bỏ qua → bấm không phản hồi. Phím mũi tên hoạt động vì đã mang cờ
(0x125–0x128), Delete (0x12e) và Win (0x15b) cũng vậy.

### Cách sửa

`lib/rdp_input.dart`: thêm cờ `vkExtKey` (0x100, hằng số đã có sẵn):

- `'PgUp': vkExtKey | 0x21` (= 0x121)
- `'PgDn': vkExtKey | 0x22` (= 0x122)
- `'End': vkExtKey | 0x23` (= 0x123)
- `'Home': vkExtKey | 0x24` (= 0x124)

Với 0x121, JNI tra bảng mở rộng, thấy VK_PRIOR ở scancode 0x49, trả
0x49|0x100 → đặt `KBD_FLAGS_EXTENDED`, gửi mã 0x49: đúng phím PgUp mở
rộng. Agent mode không đổi (đã có `{PGUP}`/`{PGDN}`/`{HOME}`/`{END}`
từ bước 24).

## Việc 3: Sửa lỗi mở lại từ đa nhiệm bị kẹt "Đang kết nối..."

### Triệu chứng

Đang kết nối (hoặc đã kết nối), bấm nút đa nhiệm (recents) rồi mở lại
app: màn hình hiện "Đang kết nối..." hoài không xong; bấm Back rồi vào
lại mới được.

### Nguyên nhân (kiểm chứng bằng đọc code — không tái hiện được trên VM)

Overlay "bận" hiện khi `submitting || state == 'connecting' ||
state == 'disconnecting'`, và luồng kết nối KHÔNG có timeout hay đường
phục hồi nào:

1. Khi app xuống nền, kết nối RDP có thể rớt (mạng bị treo, server
   đóng phiên). FreeRDP tự nối lại (mặc định `AutoReconnectMaxRetries
   = 20`, mỗi lần thử lại có timeout mạng riêng) và gọi
   `OnReconnecting` → native báo state `'connecting'`. 20 lần thử lại
   chậm có thể kéo dài hàng phút — với người dùng là "hoài".
2. Sự kiện trạng thái native có thể bị mất: `RdpPlugin.change()` đăng
   lên main handler và kiểm tra `if (!disposed)` lúc gửi — nếu view bị
   dispose giữa chừng, sự kiện bị nuốt, Dart giữ state cũ mãi.
3. Khi quay lại từ nền, Dart KHÔNG hỏi lại native: hàm
   `didChangeAppLifecycleState` ở `_RemotePageState` chỉ khởi động lại
   polling của chế độ agent, không làm gì cho chế độ RDP. Không có chỗ
   nào đồng bộ lại trạng thái sau khi background.

Kết quả: spinner không còn đường thoát ngoài nút Back (PopScope ngắt
kết nối rồi về Home).

### Cách sửa (2 lớp, đều ở phía Dart, không sửa native)

1. **Đồng bộ khi quay lại từ nền** (`lib/main.dart`,
   `_RemotePageState.didChangeAppLifecycleState` + `_resumeRdp()` mới):
   khi `resumed` ở chế độ RDP, gọi `rdpController.status()` và nhận
   snapshot native làm state Dart. Listener `connectionChanged` của pane
   phản ứng như thường (điền lại user/pass khi failed/disconnected, vũ
   trang watchdog khi vẫn busy).
2. **Watchdog chống kẹt** (`lib/rdp_surface.dart`,
   `_RdpConnectionPaneState`): `connectionChanged()` vũ trang lại timer
   30 giây mỗi khi state là 'connecting'/'disconnecting'. Mỗi lần đổi
   phase (creating → auth → connecting) vũ trang lại, nên kết nối chậm
   nhưng đang tiến triển không bị cắt. Nếu state không đổi trong 30 giây
   (kết nối bình thường chỉ mất vài giây), `_onBusyTimeout()` gọi
   `disconnect()` để hủy attempt bên native; nếu native không báo lại,
   ép state Dart thành `'failed'` với lỗi "Kết nối quá lâu, đã hủy. Hãy
   bấm Kết nối lại." — spinner biến mất, form hiện lại kèm user/pass đã
   lưu, An bấm "Kết nối lại" là xong. Nút "Ngắt" và nút Back vẫn hủy
   được như trước.

Lưu ý: timer 30 giây là giới hạn trên cho trạng thái "bận", không phải
thời gian kết nối tối đa — kết nối đang đổi phase được gia hạn liên tục.

## Việc 4: Chỉnh lại kích cỡ bàn phím cho màn hình gập (Fold6)

### Vấn đề

Trước đây mỗi hàng phím là `Expanded`, nên chiều cao phím = (nửa màn
hình dưới)/6. Trên màn hình gập (hẹp, cao) phím bị kéo thành hình chữ
nhật đứng, nhãn 13px trông lọt thỏm; nhãn dài PgUp/PgDn/Home/End bị
FittedBox thu nhỏ xíu. Trên màn hình mở (rộng) phím lại to quá.

### Cách sửa (`lib/main.dart`, `keyboardPanel()` + `laptopKey()`)

- Chiều cao hàng giờ theo **chiều rộng phím** (16.25 units là hàng rộng
  nhất): `rowHeight = (maxWidth / 16.25 * 1.15).clamp(44, 64)`, đồng
  thời không vượt quá không gian có sẵn
  (`(maxHeight - 8) / sốHàng`, chế độ agent có 7 hàng vì thêm hàng
  "Click trái/phải"). Phím không bao giờ thấp hơn 44dp (bấm thoải mái)
  hay cao hơn 64dp (cỡ phím laptop).
- Hàng phím là `SizedBox` chiều cao cố định thay vì `Expanded`; cả cụm
  bàn phím được căn giữa trong nửa dưới. Tỉ lệ 50/50 (màn remote / bàn
  phím) KHÔNG đổi — chỉ phần nền deck thừa ra khi nửa dưới cao hơn bàn
  phím.
- Cỡ chữ nhãn theo chiều cao hàng: `kbLabelSize =
  (rowHeight * 0.30).clamp(12, 16)` (field trạng thái do
  `keyboardPanel()` tính trước mỗi lần build, `laptopKey()` đọc). Nhãn
  dài vẫn được FittedBox thu nhỏ cho vừa phím (không bị cắt) — trên màn
  hẹp, nhãn PgUp/PgDn/Home/End to bằng đúng chiều rộng phím cho phép,
  đó là giới hạn vật lý của 16.25 phím trên màn hẹp.
- Chế độ agent dùng chung `keyboardPanel()` nên cũng được hưởng.

## Việc 5: Cỡ phím hàng F (Delete to hơn, F1–F12 bằng phím số)

- Hàng 1 trước đây tổng 14 units (Esc 1 + F1–F12 + Del 1) nên mỗi phím
  rộng hơn phím số ở hàng 2 (16 units). Giờ hàng 1 cũng tổng 16 units:
  Esc 1.5, F1–F12 mỗi phím 1, Del 2.5. F1–F12 rộng đúng bằng phím số;
  Delete to hơn hẳn (2.5× phím số).
- Hàng 1 vẫn lấp đầy đủ chiều ngang, không phím nào bị cắt.

## File đổi

- `lib/rdp_input.dart` — VK PgUp/PgDn/Home/End thêm cờ extended.
- `lib/main.dart` — phím Right; đồng bộ trạng thái khi resume
  (`_resumeRdp`); bàn phím thích ứng (`rowHeight`, `kbLabelSize`,
  hàng `SizedBox` + căn giữa); hàng F 16 units (Esc 1.5, Del 2.5).
- `lib/rdp_surface.dart` — watchdog 30 giây chống kẹt connecting.
- `test/rdp_input_test.dart` — VK mới (0x121–0x124); `shiftedLabel`
  của 'Right'.
- `test/rdp_surface_test.dart` — test Left/Right; VK nav mới; 4 test
  mới: watchdog 30s, resume đồng bộ lại state, hàng F, bàn phím ở 2 cỡ
  màn hình.
- `test/remote_test.dart` — hàng dưới Left/Space/Right (chế độ agent).

Không đụng: fixed key (`build.gradle`, 2 workflow), `proguard-rules.pro`,
PIN, Caps Lock (bước 22), lưu user/pass và danh sách kết nối (bước 23).

## Kiểm chứng

- `flutter analyze`: 0 issue.
- `flutter test`: 70/70 pass (66 cũ + 4 mới). 4 test mới đã chạy riêng
  lẻ và pass: watchdog, resume, hàng F, 2 cỡ màn hình.

## Cách test trên Fold6

1. **Phím Right**: kết nối RDP, bấm phím "Right" bên phải Space → menu
   chuột phải hiện tại con trỏ (ví dụ trên desktop). Phím "Left" bên
   trái Space vẫn click trái. Cả 2 chế độ Chạm/Trackpad.
2. **PgUp/PgDn/Home/End**: mở Notepad hoặc trang dài, bấm PgUp/PgDn
   cuộn trang, Home/End nhảy đầu/cuối dòng (hoặc đầu/cuối tài liệu với
   Ctrl). Cả 4 phím phải phản hồi ngay.
3. **Kẹt "Đang kết nối..."**: kết nối RDP, bấm nút đa nhiệm (recents),
   mở app khác một lúc rồi quay lại app Ace Remote từ đa nhiệm → không
   còn spinner kẹt; hoặc desktop hiện lại, hoặc form kết nối hiện lại
   để bấm "Kết nối lại". (Trường hợp xấu nhất: nếu vẫn kẹt, sau tối đa
   30 giây spinner tự biến mất và hiện "Kết nối quá lâu, đã hủy.")
4. **Cỡ bàn phím**: gập màn hình (màn hẹp) — phím không còn bị kéo cao,
   nhãn đọc được, không bị cắt; mở màn hình (màn rộng) — phím cân đối,
   không quá to. Xoay/gập-mở lại vẫn cân đối.
5. **Hàng F**: phím F1–F12 rộng bằng phím số hàng dưới; phím Delete to
   hơn rõ rệt.
