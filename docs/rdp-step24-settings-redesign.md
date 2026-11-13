# Bước 24 — Cài đặt mới + phím Left + mũi tên T ngược + loading hiện đại + cột điều hướng

Base: `5f537a7` (bước 23), branch `rdp-prototype`. An test bản run #11
(bước 22 + bước 23) và nói "gần hoàn thiện rồi", còn một số chỗ cần chỉnh
tiếp. Bước 24 làm cả 6 việc đó: việc 1 + 3 ở commit `7bd52cb`, việc 2 + 4 +
5 + 6 ở commit này (trên `7bd52cb`).

## Việc 1: Làm lại màn hình Cài đặt

Ảnh An gửi (màn hình "Cài đặt" cũ) có: ô "Địa chỉ agent (Base URL)"
`http://100.101.127.41:18765`, nút "Kiểm tra kết nối", dropdown "Giao diện"
("Theo điện thoại"), dropdown "Tốc độ ảnh" ("Bình thường • 2 ảnh/giây"),
đoạn ghi chú về agent/WoL, nút "Lưu cài đặt". An nói: "1 menu cài đặt này
hết giá trị rồi pk em. Em đổi thành cài đặt chế độ sáng tối, theo máy tính
đi em. Với làm hiện đại luôn nha."

### Đã bỏ
- Ô "Địa chỉ agent (Base URL)" và nút "Kiểm tra kết nối" — app giờ nối
  bằng RDP; host/port/user/pass cấu hình theo từng kết nối trong màn hình
  Edit trên trang chính (bước 23).
- Dropdown "Tốc độ ảnh" — tốc độ ảnh của agent không còn dùng ở bản RDP.
- Đoạn ghi chú về agent/WoL ("Máy ngủ hẳn thì không gọi dậy được ở v1...").
- Nút "Lưu cài đặt" — không còn gì để lưu ở màn hình này nữa.

### Giữ lại và làm rõ: chế độ Sáng/Tối
- 3 lựa chọn trong một card Material 3 (dùng `RadioGroup<ThemeMode>`):
  - **Sáng** — giao diện sáng (`ThemeMode.light`).
  - **Tối** — giao diện tối (`ThemeMode.dark`).
  - **Theo điện thoại** — theo cài đặt hệ thống của điện thoại
    (`ThemeMode.system`, mặc định).
- Chọn xong áp dụng **ngay lập tức** (gọi `onThemeChanged`, lưu
  `ace_remote_v1_theme` vào SharedPreferences như trước) — không cần bấm
  lưu. Dòng ghi chú cuối trang nhắc: cài đặt kết nối (địa chỉ, cổng, tài
  khoản) nằm trong màn hình sửa từng kết nối trên trang chính.
- `SettingsPage` đổi API: chỉ còn `theme` + `onThemeChanged(ThemeMode)`.
  Code agent (`Agent`, `pollMs`) vẫn nằm trong code cho bản non-RDP nhưng
  màn hình Cài đặt không còn hiển thị/chỉnh chúng nữa.

## Việc 3: Nhãn phím đổi theo Shift

An nói: "3 khi nhấn shift thì bàn phím đổi theo phím sẽ tác dụng khi nhấn
shift nha em. Ví dụ số 2 là @"

### Cách hoạt động
- Khi Shift đang được arm (one-shot, phím Shift đang sáng), nhãn trên bàn
  phím đổi sang ký tự Shift của phím đó; bấm xong 1 phím thì Shift tự tắt
  và nhãn trở về bình thường.
- Phím vẫn gửi **nhãn gốc** + modifier Shift đang arm (RDP: `rdpKey` gửi
  Shift down, VK của phím gốc, Shift up; agent: `/key` với combo
  `Shift+<phím>`), nên ký tự Windows nhận được khớp đúng với nhãn đang
  hiển thị (bấm phím đang hiện "@" thì Windows nhận "@").
- Chỉ `modifiers.contains('Shift')` mới đổi nhãn. Caps Lock (bước 22) là
  toggle thật, không bao giờ vào `modifiers`, nên bật Caps Lock không đổi
  nhãn phím số — đúng hành vi phím thật.
- Phím chữ đã hiển thị chữ hoa sẵn nên không đổi visibly khi Shift arm;
  phím tên (Esc, Tab, Enter...) không có ký tự Shift nên giữ nguyên.

### Bảng ký tự Shift (bố cục US)

| Phím | ` | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 0 | - | = | [ | ] | \ | ; | ' | , | . | / |
|------|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Shift | ~ | ! | @ | # | $ | % | ^ | & | * | ( | ) | _ | + | { | } | \| | : | " | < | > | ? |

Bảng nằm trong `lib/rdp_input.dart` (`shiftKeyLabels` + `shiftedLabel()`),
hiển thị qua `displayLabel` trong `laptopKey()` (`lib/main.dart`). Áp dụng
cho cả 2 chế độ vì dùng chung widget phím.

## Việc 2: 2 phím chuột trái "Left" kẹp 2 bên phím Space

An hỏi gợi ý cách click trái (do giờ rê chuột trên bàn phím, muốn click
trái phải với tay lên chạm màn hình; chuột phải 2 ngón thì chạm màn hình
hay bàn phím đều được). Muse gợi ý 2 phím "Left" kẹp 2 bên phím Space vì
không đụng với gõ phím (phím riêng, không phải cử chỉ — double-tap để
click sẽ bị nhận nhầm khi gõ 2 chữ giống nhau liên tiếp như "ll"), 2 bên
nên ngón cái nào cũng bấm được, dùng được cả 2 chế độ, luôn nhìn thấy
khỏi phải nhớ cử chỉ. An chốt: "Ok, làm 2 phím Left 2 bên Space đi em".

### Cách hoạt động
- Hàng phím dưới cùng giờ là: Ctrl, Win, Alt, **Left**, Space, **Left**,
  Alt, Ctrl, ←, ↓, →. Mỗi phím "Left" bằng cỡ phím Alt (1.25 units).
- Bấm phím "Left" nào cũng gửi **click trái tại vị trí con trỏ hiện
  tại**: RDP mode gọi `RdpController.clickAtLastPosition('left')` (kênh
  `'click'`, native `clickAt` với `PTRFLAGS_LBUTTON`); agent mode gọi
  `click('left')` (endpoint `/click` tại cursor hiện tại). Dùng được cả
  chế độ Chạm lẫn Trackpad.
- Phím Space thu hẹp 5 -> 4.5 để vừa 2 phím Left (hàng dưới tổng 16.25,
  bằng hàng trên, nên Ctrl/Win/Alt và các phím mũi tên giữ nguyên cỡ).
- **Quan trọng:** phím "Left" KHÔNG đi qua `rdpKey` — nhãn `'Left'` trong
  `rdpVirtualKey` là phím mũi tên trái (VK_LEFT 0x125). `laptopKey` có tham
  số mới `mouseButton: 'left'`; `press()` rẽ nhánh trước khi gửi phím.
  Modifier đang arm (Shift...) được giữ nguyên khi click, để Shift+click
  chọn vùng vẫn hoạt động. Chưa kết nối RDP thì bấm Left không gửi gì.
- Màu phím giữ nguyên như các phím khác (nền xám tối, chữ trắng) — theo
  ràng buộc của An, KHÔNG tô xanh ngọc.
- Highlight khi nhấn: `pressedLabel` lưu nhãn phím (String), 2 phím Left
  mang `keyId` riêng (`Left-1` / `Left-2`) nên bấm phím nào chỉ phím đó
  sáng (không sáng cả 2). Lưu ý: `pressedLabel` KHÔNG dùng GlobalKey vì
  `laptopKey` tạo GlobalKey mới mỗi lần build nên id cũ sẽ lệch sau
  rebuild — đã thử và làm hỏng test highlight.

## Việc 4: Phím mũi tên xếp theo hình chữ T ngược

An nói: "chỗ phím 4 hướng mũi tên đang trên 1 hàng. Anh muốn mũi tên lên
nằm trên. Theo đúng hướng 4 mũi tên đó em." An xem layout trước rồi duyệt
với 3 ràng buộc: "Mũi tên phải nút lên xuống bằng nhau nha em. Phím thì
như hiện tại nha. Đừng chỉnh kiểu màu."

### Layout mới
```
        ↑
    ←   ↓   →
```
- Phím **↑** nằm ở cuối hàng Shift (hàng 4), phía trên phím ↓; 3 phím
  **← ↓ →** ở hàng dưới cùng (hàng 5).
- **↑ và ↓ bằng nhau:** cả 4 phím mũi tên đều là phím đầy đủ, cùng cỡ
  (1 unit, không half-height). Hàng 4 và hàng 5 cùng tổng 16.25 nên ↑
  rộng đúng bằng ↓. Để vừa ↑, phím Shift phải thu hẹp 2.75 -> 2.0 (phím
  duy nhất đổi cỡ ngoài Space; các phím còn lại giữ nguyên cỡ).
- **Không đổi màu:** tất cả phím giữ nền xám tối / chữ trắng như hiện
  tại (màu xanh ngọc trong bản xem trước HTML của Muse chỉ để minh họa).

## Việc 5: Loading khi đang kết nối — hiện đại (Material 3)

An nói: "Thêm nữa chỗ thông báo kết nối này vẫn chưa hiện đại, nên để
loading kiểu hiện đại." Hộp cũ: hộp đen bo góc lớn giữa màn hình remote,
chỉ có dòng "Đang kết nối..." và nút "Ngắt" xanh ngọc.

### Đã đổi
- Hộp cũ (Card lớn, chữ phase + nút "Ngắt" xếp dọc) → **thẻ nhỏ gọn nằm
  giữa màn hình**: một hàng ngang gồm vòng xoay loading
  (`CircularProgressIndicator`, 20x20, stroke 2.5) + dòng trạng thái theo
  phase + nút "Ngắt" dạng text button.
- Giữ nguyên phase text của bước 23: "Đang tạo phiên…" /
  "Đang xác thực…" / "Đang kết nối…" / "Đang ngắt kết nối…".
- Giữ nguyên chức năng: vẫn hiện đúng phase, vẫn hủy được bằng nút
  "Ngắt" (và bằng nút Back). Card tự co theo nội dung (maxWidth 400
  như cũ) nên không che quá nhiều màn hình.

## Việc 6: Cột phím điều hướng bên phải (PgUp/PgDn/Home/End)

An gửi ảnh góc phải một bàn phím cơ (kiểu Keychron) và nói: "Khúc bên
phải em làm kiểu này đi em. Có thêm pageup, down home end. 4 phím mũi
tên vẫn đều."

### Layout mới
- Cột ngoài cùng bên phải, xếp dọc: **PgUp** ở hàng số (hàng 1, cùng hàng
  Backspace), **PgDn** ở hàng QWERTY (hàng 2, cùng hàng `\`), **Home** ở
  hàng ASDF (hàng 3, cùng hàng Enter), **End** ở hàng Shift (hàng 4, cùng
  hàng ↑, ngoài cùng bên phải). Phím **Del** ở hàng F đã có sẵn, giữ
  nguyên.
- 4 phím mũi tên giữ nguyên hình chữ T ngược (việc 4) và vẫn đều nhau.
- Các phím khác giữ nguyên vị trí, cỡ và màu. Thêm cột mới nhưng không
  phím nào bị cắt (hàng 1-3 tổng 16, hàng 4-5 tổng 16.25).
- VK qua RDP (`rdpVirtualKey`): PgUp = 0x21 (VK_PRIOR), PgDn = 0x22
  (VK_NEXT), End = 0x23 (VK_END), Home = 0x24 (VK_HOME). Agent mode:
  `sendKeysChord` thêm PgUp -> `{PGUP}`, PgDn -> `{PGDN}`, Home ->
  `{HOME}`, End -> `{END}` (tên SendKeys viết hoa; không thêm thì sẽ
  thành `{PgUp}` mà SendKeys không nhận).

## File đổi
- `lib/main.dart` — `SettingsPage` mới (chỉ Sáng/Tối/Theo điện thoại,
  `RadioGroup`, áp dụng ngay); 2 chỗ gọi `SettingsPage` đổi API;
  `laptopKey()` thêm `displayLabel` theo Shift, thêm tham số `mouseButton`
  + `keyId`; hàng phím 1-5 thêm cột điều hướng, hàng 4 thêm ↑ + End
  (Shift phải 2.0), hàng 5 thêm 2 phím Left (Space 4.5); `pressedLabel`
  theo nhãn/keyId.
- `lib/rdp_input.dart` — thêm `shiftKeyLabels` + `shiftedLabel()`; thêm
  VK PgUp/PgDn/End/Home.
- `lib/agent.dart` — `sendKeysChord` thêm PgUp/PgDn/Home/End.
- `lib/rdp_surface.dart` — loading kết nối: thẻ nhỏ gọn với
  `CircularProgressIndicator` + phase text + nút "Ngắt".
- `test/settings_test.dart` (mới) — Cài đặt chỉ còn 3 lựa chọn, không còn
  mục agent; bấm chọn thì áp dụng ngay; mở trang với theme hiện tại đã chọn.
- `test/rdp_input_test.dart` — test `shiftedLabel()` cho toàn bộ bảng +
  phím chữ/phím tên giữ nguyên; test VK PgUp/PgDn/End/Home;
  `shiftedLabel('Left')` giữ nguyên.
- `test/rdp_surface_test.dart` — widget test RDP: Shift arm thì "2" thành
  "@" (kèm "1"→"!", "0"→")", "-"→"_"); bấm "@" gửi đúng chord Shift down
  + VK 0x32 + Shift up, rồi nhãn trở về "2"; test 2 phím Left (đúng vị
  trí 2 bên Space, bấm gửi `click` left, chưa kết nối thì không gửi gì);
  test mũi tên T ngược (↑ ở hàng 4, ← ↓ → ở hàng 5, ↑ = ↓ về kích cỡ,
  bấm mỗi phím gửi đúng VK); test cột điều hướng (đúng vị trí, bấm gửi
  đúng VK); test loading (spinner + phase text, bấm "Ngắt" hủy).
- `test/remote_test.dart` — cập nhật hàng phím 1-5 (cột điều hướng, ↑,
  2 phím Left); test bấm "Left" (agent mode) gửi `/click` left; test bấm
  PgUp/PgDn/Home/End gửi `{PGUP}`/`{PGDN}`/`{HOME}`/`{END}`.
- `docs/rdp-step24-settings-redesign.md` — doc này.

Không đụng: fixed key (`build.gradle`, 2 workflow), `proguard-rules.pro`,
logic PIN, logic Caps Lock bước 22, logic lưu user/pass và danh sách kết
nối bước 23.

## Kiểm chứng
- `flutter analyze`: **0 issue** (dùng `RadioGroup` thay cho
  `RadioListTile.groupValue`/`onChanged` đã deprecated; các tile `const`).
- `flutter test`: **66/66 pass** (62 cũ + 4 mới: Left RDP, mũi tên T
  ngược, cột điều hướng, loading hiện đại).

## Cách test trên Fold6
1. Mở app → bấm icon bánh răng (Cài đặt): chỉ còn mục "Giao diện" với 3
   lựa chọn Sáng / Tối / Theo điện thoại; không còn Base URL, "Kiểm tra
   kết nối", "Tốc độ ảnh", ghi chú agent, nút "Lưu cài đặt". Chọn "Tối" →
   app đổi sang tối ngay; chọn "Sáng" → sáng ngay; mở lại app vẫn giữ lựa
   chọn đã chọn.
2. Kết nối RDP vào máy ace → bấm phím Shift (trái): hàng số đổi thành
   `~ ! @ # $ % ^ & * ( ) _ +`, các phím `[ ] \ ; ' , . /` đổi thành
   `{ } | : " < > ?`. Bấm phím đang hiện "@" → gõ ra "@" trên Windows.
   Bấm xong 1 phím → nhãn trở về bình thường. Bấm Caps Lock → nhãn phím
   số không đổi (chỉ chữ hoa).
3. Hàng phím dưới: 2 phím "Left" kẹp 2 bên phím Space (bằng cỡ phím Alt,
   màu như các phím khác). Rê chuột trên bàn phím rồi bấm phím "Left" →
   click trái tại vị trí con trỏ (không cần với tay lên chạm màn hình).
4. Cụm mũi tên hình chữ T ngược: ↑ ở hàng Shift (phía trên ↓), ← ↓ →
   ở hàng dưới; cả 4 phím cùng cỡ. Bấm ↑/↓/←/→ di chuyển đúng hướng.
5. Cột phải: PgUp (hàng số), PgDn (hàng QWERTY), Home (hàng ASDF), End
   (hàng Shift). Bấm PgUp/PgDn cuộn trang, Home/End về đầu/cuối dòng.
6. Ngắt kết nối rồi kết nối lại: hộp loading nhỏ gọn giữa màn hình, có
   vòng xoay + dòng trạng thái theo từng bước ("Đang tạo phiên…" /
   "Đang xác thực…" / "Đang kết nối…"); bấm "Ngắt" thì hủy được.
