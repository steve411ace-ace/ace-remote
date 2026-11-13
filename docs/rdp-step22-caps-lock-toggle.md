# Bước 22 — Phím Caps Lock thành bật/tắt thật (toggle)

## Vấn đề (An dặn 14/11 03:24)
Phím Caps trên bàn phím laptop của app đang hoạt động như Shift one-shot: nhấn Caps xong bấm 1 phím thì tự tắt. An muốn Caps Lock thật: nhấn 1 lần thì BẬT (chữ hoa tới khi nhấn lại), nhấn lần nữa thì TẮT.

## Nguyên nhân
- `lib/rdp_input.dart`: `'Caps': 0xa0` — Caps map tới VK_LSHIFT (0xA0), cùng mã với Shift.
- `lib/main.dart` `rdpKey()`: dòng `if (key == 'Caps') key = 'Shift';` đổi Caps thành Shift ngay đầu hàm.
- Vì 'Shift' nằm trong danh sách modifier `['Win', 'Ctrl', 'Alt', 'Shift']`, Caps bị đưa vào tập `modifiers` (one-shot): bấm phím tiếp theo thì Shift được áp dụng rồi `modifiers.clear()` xóa đi.
- Phím Caps trên bàn phím (`laptopKey('Caps', command: 'Shift', modifier: true)`) cũng mang command 'Shift' nên càng củng cố hành vi này.

## Thay đổi
| File | Thay đổi |
|---|---|
| `lib/rdp_input.dart` | `'Caps': 0xa0` → `'Caps': 0x14` (VK_CAPITAL — mã Caps Lock của Windows) |
| `lib/main.dart` | Bỏ dòng đổi Caps thành Shift; thêm nhánh xử lý 'Caps' riêng TRƯỚC logic modifier trong `rdpKey()`: toggle biến `capsLockOn` và gửi một lần nhấn VK_CAPITAL (down + up) xuống RDP để Windows tự toggle trạng thái; KHÔNG đưa Caps vào tập `modifiers`, KHÔNG xóa sau 1 phím |
| `lib/main.dart` | Thêm state `bool capsLockOn = false;` cạnh `modifiers`; phím Caps hiển thị sáng (màu `0xff505762`, cùng kiểu highlight của phím modifier) khi đang BẬT |
| `lib/main.dart` | `laptopKey.press()` ở chế độ RDP: phím Caps luôn gửi `'Caps'` tới `rdpKey()` (dù widget mang command 'Shift' cho chế độ agent) |
| `test/rdp_input_test.dart` | `'Caps': 0xa0` → `'Caps': 0x14` |
| `test/rdp_surface_test.dart` | Test mới 'Caps Lock toggles with VK_CAPITAL and stays on across keys' |

## Không đổi
- **Phím Shift vẫn one-shot như cũ** (nhấn Shift rồi bấm 1 phím thì tắt; test khẳng định lại).
- **Chế độ agent (không phải RDP) không đổi**: ở đó Caps vẫn arm Shift one-shot như trước (test cũ ở `remote_test.dart` vẫn pass, vì `laptopKey.press()` chỉ đổi đường RDP; `selected` của Caps ở agent mode vẫn là `modifiers.contains('Shift')`).
- Không đụng logic Trackpad, ẩn/hiện bàn phím, header tự ẩn, lưu username/mật khẩu (bước 21), không đụng fixed key (build.gradle, 2 workflow), không đụng `proguard-rules.pro`, không khôi phục PIN.
- Không sửa Kotlin/native: VK_CAPITAL (0x14) đi qua đúng đường `sendKey` đã có; server Windows tự toggle trạng thái Caps Lock.

## Hạn chế (cần biết)
- Trạng thái `capsLockOn` là trạng thái app tự theo dõi (toggle mỗi lần nhấn phím Caps trên màn hình). Nếu An bấm Caps Lock trên phím rời / phím vật lý thì Windows đổi trạng thái nhưng app không biết → phím Caps trên màn hình có thể hiển thị lệch với trạng thái thật. Cách khắc phục khi đó: bấm phím Caps trên màn hình 1 lần để đồng bộ lại (hoặc bấm 2 lần để về đúng trạng thái mong muốn).
- Trạng thái không được reset khi ngắt/kết nối lại: nếu nối lại cùng phiên Windows thì trạng thái Caps Lock của server vẫn giữ nguyên nên không reset là đúng; nếu là phiên mới thì có thể lệch — bấm Caps trên màn hình để đồng bộ lại như trên.

## Kiểm chứng (VM, Flutter 3.50.0)
- `flutter analyze`: **No issues found!**
- `flutter test`: **42/42 pass** (41 cũ + 1 mới). Test mới chạy riêng lẻ pass; toàn bộ `test/rdp_surface_test.dart` 11/11 pass.
- Test mới khẳng định: nhấn Caps lần 1 → gửi đúng 1 cặp VK_CAPITAL down/up (`0x14`), `capsLockOn == true`, phím sáng; bấm phím 'A' sau đó → chỉ gửi `0x41` down/up (không kèm Shift), `capsLockOn` vẫn true; nhấn Caps lần 2 → gửi lại 1 cặp VK_CAPITAL, `capsLockOn == false`, phím hết sáng; Shift vẫn one-shot (nhấn Shift rồi 'A' → Shift down, A down/up, Shift up, `modifiers` rỗng, `capsLockOn` vẫn false).

## Cách test trên Fold6
1. Kết nối RDP, mở Notepad (hoặc ô nhập chữ).
2. Bấm phím **Caps** 1 lần → phím Caps sáng lên.
3. Gõ `asdf` → hiện `ASDF` (chữ hoa).
4. Bấm thêm vài phím chữ khác → vẫn chữ hoa (không tự tắt sau 1 phím).
5. Bấm phím **Caps** lần nữa → phím Caps hết sáng.
6. Gõ `asdf` → hiện `asdf` (chữ thường).
7. Kiểm tra Shift vẫn như cũ: bấm **Shift** rồi gõ 1 chữ → chỉ chữ đó hoa, chữ sau thường.
