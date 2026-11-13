# Bước D — keyboard và touch input

Ngày 2026-11-13 UTC; branch `rdp-prototype`, nền `d9d3e14`.
Đã đọc step11 (e), B2, C và đối chiếu source FreeRDP 3.33.0 local.
Gốc J: `/home/hatch/workspace/FreeRDP-3.33.0/client/Android/Studio/freeRDPCore/src/main/java/com/freerdp/freerdpcore/`.

## Public API và map phím

Chỉ gọi `LibFreeRDP.sendKeyEvent(long,int,boolean)` (J/services/LibFreeRDP.java:575–578)
và `sendCursorEvent(long,int,int,int)` (:570–573); không native private/reflection/JNI mới.
Channel có `key {vk,down}`, `cursor {x,y,flags}`, `click {button}` (left/right).
Input ngoài attempt connected, handle khác 0, chưa disposed/stopping/terminal bị bỏ qua;
method trả success(null). Công việc giữ identity attempt và kiểm tra lại dưới lock trên
single-thread executor, serialize với start/teardown; cursor còn yêu cầu surface ready.

Nguồn bảng: J/utils/KeyboardMapper.java constants :35–205, keymapAndroid :236–340;
VK_EXT_KEY=0x100 (:204–205). Giá trị dưới đây là VK cuối cùng, không phải Android keycode.

| Label/command Dart | VK hex | Constant/nguồn KeyboardMapper |
| --- | --- | --- |
| A B C D E F G H I J K L M | 41 42 43 44 45 46 47 48 49 4A 4B 4C 4D | VK_KEY_A…M, :82–94; map :247–259 |
| N O P Q R S T U V W X Y Z | 4E 4F 50 51 52 53 54 55 56 57 58 59 5A | VK_KEY_N…Z, :95–107; map :260–272 |
| a…z | như A…Z | Chuyển label sang hoa để tìm VK; Shift do Windows xử lý |
| 0 1 2 3 4 5 6 7 8 9 | 30 31 32 33 34 35 36 37 38 39 | VK_KEY_0…9, map :236–245 |
| Esc | 1B | VK_ESCAPE |
| Backspace | 08 | VK_BACK (Android DEL) |
| Tab | 09 | VK_TAB |
| Enter | 0D | VK_RETURN |
| Space | 20 | VK_SPACE |
| F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12 | 70 71 72 73 74 75 76 77 78 79 7A 7B | VK_F1…F12; map :307–318 |
| Left Up Right Down | 125 126 127 128 | VK_LEFT/UP/RIGHT/DOWN OR EXT, :283–286 |
| Delete (label Del) | 12E | VK_DELETE OR EXT, :291 |
| Win | 15B | VK_LWIN OR EXT, ACTION_DOWN/UP :456–539 |
| Shift; Caps (command Shift) | A0 | VK_LSHIFT, ACTION_DOWN |
| Ctrl | A2 | VK_LCONTROL, ACTION_DOWN |
| Alt | A4 | VK_LMENU, ACTION_DOWN |
| `-` | BD | VK_OEM_MINUS, :294 |
| `=` | BB | VK_OEM_PLUS, :295 |
| `[` | DB | VK_OEM_4, :296 |
| `]` | DD | VK_OEM_6, :297 |
| `\` | DC | VK_OEM_5, :298 |
| `;` | BA | VK_OEM_1, :299 |
| `'` | DE | VK_OEM_7, :300 |
| backtick | C0 | VK_OEM_3, :301 |
| `,` | BC | VK_OEM_COMMA, :302 |
| `.` | BE | VK_OEM_PERIOD, :303 |
| `/` | BF | VK_OEM_2, :304 |

Caps trên bàn phím này đóng vai Shift one-shot, **không phải CapsLock thật**;
VK_CAPITAL=0x14 tồn tại trong source nhưng không dùng cho label Caps.
Label không hỗ trợ trả null. Không gửi Unicode/typeText HTTP trong RDP.

## Modifier và quyền sở hữu controller

RemotePage sở hữu controller chung, truyền cho pane/surface và dispose cùng page.
Pane tự tạo/dispose controller khi không được truyền. Chưa attach: sendKey,
sendCursor, clickAtLastPosition no-op; chưa connected: nhấn phím không arm/gửi.
Chỉ mở AbsorbPointer trong nhánh RDP, giữ hai nửa 50/50 và hành vi agent-mode.

Shift/Ctrl/Alt toggle arming, chưa gửi event. Win lần đầu arm; lần hai remove
và gửi Win down/up một mình để mở Start. Phím thường lấy snapshot modifiers,
clear one-shot và xếp một chord vào queue Dart để các chord không xen kẽ:
modifier down theo **Win, Ctrl, Alt, Shift**, key down/up, modifier up ngược lại.
Đây là thứ tự yêu cầu của bước D. Source local ACTION_DOWN :456–539 thực tế
là Ctrl, Alt, Win, Shift; áp dụng cùng mẫu bracket key bằng modifier nhưng
không tuyên bố thứ tự app trùng nguyên văn mapper. Windows tự xử lý Shift,
VK chữ không đổi. Click trái/phải gọi native click ở vị trí cuối, xóa arming.

KeyboardSurface trong nửa bàn phím RDP: onMove/onScroll/onDrag/onClick đều no-op;
chỉ tap phím qua keyAt có tác dụng. Trackpad tương đối cần vị trí con trỏ hiện
thời mà Dart không biết. Agent-mode vẫn dùng HTTP như trước.

## Tọa độ và cử chỉ

Kotlin gắn OnTouchListener trực tiếp SurfaceView. Chỉ nhận khi connected,
bitmap có sẵn, surface ready; ngoài phiên trả false. bw/bh lưu khi
OnSettingsChanged/OnGraphicsResize tạo bitmap. Surface destroyed hủy gesture,
không gửi cursor khi surface không ready.

Cùng công thức render và hàm Dart pure mapTouchToFramebuffer:

```
scale = min(viewW / bw, viewH / bh)
offsetX = (viewW - bw * scale) / 2
offsetY = (viewH - bh * scale) / 2
fbX = (touchX - offsetX) / scale
fbY = (touchY - offsetY) / scale
```

Chấp nhận 0 <= fbX < bw, 0 <= fbY < bh. Vùng đen letterbox trả null trong
Dart; Kotlin nuốt event, không clamp/không gửi tọa độ ngoài bitmap. Ra vùng đen hủy long-press, không gửi cursor (kể cả up ngoài ảnh); nếu đang
kéo, release phải chờ event hợp lệ tiếp theo/cancel hợp lệ hoặc phiên kết thúc.
Đây là giới hạn của chính sách bỏ qua hoàn toàn sự kiện ngoài bitmap.
Điểm hợp lệ lưu lastX/lastY dạng int (truncate). Chưa chạm thì mặc định tâm
framebuffer bw/2,bh/2; resize làm điểm cũ ngoài bitmap cũng đặt về tâm.

| Cử chỉ | Event gửi |
| --- | --- |
| Down | MOVE tới điểm chạm; lên lịch long-press 500ms |
| Tap: down/up, dịch <12px, thời gian <500ms | MOVE, LEFT down, LEFT up |
| Move >12px | Hủy long-press; MOVE, LEFT down bắt đầu kéo; move tiếp gửi MOVE; up MOVE rồi LEFT up |
| Long-press >=500ms, dịch <=12px | Handler main: MOVE, RIGHT down/up; đánh dấu đã xử lý, up không phát left |
| Ngón thứ hai xuống | Hủy long-press, release left nếu đang kéo, vào scroll mode |
| Hai ngón move dọc | Trung bình y hai ngón, tích lũy mỗi 48px gửi 1 wheel; dy>0 xuống: 0x388; dy<0 lên: 0x278 |
| Pointer up | Giữ scroll mode qua đuôi một ngón, tới up hết mới thoát; không thành tap |
| Cancel | Hủy timer, release left nếu đang kéo, reset gesture |
| Phím Click trái/phải | MOVE tới lastX/lastY, button down/up tương ứng |

Ngưỡng dùng pixel tọa độ MotionEvent của SurfaceView. Quy ước kéo xuống =
scroll down là quy ước app, **chưa kiểm chứng trên thiết bị thật**. Không cuộn ngang.
Move pending được gộp chỉ giữ điểm mới nhất trước barrier key/button/wheel;
barrier không gộp để giữ đúng thứ tự press/drag/release. Native send chạy trên
executor dưới lock, không gọi native từ touch handler main. Long-press cũng
chỉ enqueue. Các giới hạn lock/render và lifecycle B2/C vẫn tồn tại.

| Hằng (J/utils/Mouse.java:20–30) | Hex / giá trị |
| --- | --- |
| PTRFLAGS_LBUTTON | 1000 |
| PTRFLAGS_RBUTTON | 2000 |
| PTRFLAGS_MBUTTON | 4000 |
| PTRFLAGS_DOWN | 8000 |
| PTRFLAGS_MOVE | 0800 |
| PTRFLAGS_WHEEL | 0200 |
| PTRFLAGS_WHEEL_NEGATIVE | 0100 |
| PTRFLAGS_HWHEEL | 0400 |
| WHEEL_DELTA | 0078 = 120 |

Button up bỏ DOWN. Wheel âm dùng WHEEL | NEGATIVE | (amount & 0xFF):
-120 & 0xFF = 0x88; wheel dương 120 = 0x78. Không dùng Mouse.getLeftButtonEvent,
getRightButtonEvent/getScrollEvent vì helpers :32–88 đọc swap/invert preferences
của ApplicationSettingsActivity, không có trong app Ace; constants định nghĩa
trực tiếp, comment code ghi cùng lý do.

## Kiểm chứng VM và giới hạn

Chỉ gọi Flutter tại `/home/hatch/workspace/flutter-3.50.0/bin/flutter`:

- `flutter pub get`: exit 1 trước khi chạy pub.
- `flutter analyze`: exit 1 trước analyzer; **chưa có kết quả số issue**.
- `flutter test`: exit 1 trước test runner; **chưa có số pass/fail test**.
- Cả ba bị sandbox chặn ghi SDK `bin/cache/engine.stamp.tmp.*` và `engine.realm`
  (Read-only file system). Không có quyền escalation trong phiên; không copy SDK
  hay đổi SDK. Dart formatter trong chính SDK đã chạy thành công để kiểm tra cú pháp
  Dart, không thay thế analyze/test.
- Thêm unit test VK (bao gồm chữ thường, OEM, extended, unknown) và tọa độ
  (scale nhỏ/lớn, căn giữa, letterbox, size rỗng); widget test attach mock channel,
  event connected, A/Enter/Esc/Ctrl+C, Win tap, click phải, no-op chưa attach và
  HTTP requests=0. Test cũ giữ nguyên ý nghĩa nhưng **chưa chạy được trong phiên**.
- `git diff --check`: sạch khi kiểm tra sau code/docs.

Kotlin chưa compile trên VM vì không có AAR thật; không compile bằng stub,
không chạy Gradle/build APK/CI. Hành vi bàn phím, chuột RDP thật chỉ kiểm chứng
được trên Fold6, hiện **CHƯA kiểm chứng**, gồm cuộn hai ngón và long-press timing.
Không có hover, chỉ move khi chạm/kéo. Gõ tiếng Việt có dấu chưa hỗ trợ;
bàn phím chỉ gõ trực tiếp chữ không dấu như quyết định v1.2. Không thêm lưu mật
khẩu/tài khoản, không truy cập PC của An, không push/main.

Commit đã thử với message yêu cầu nhưng bị chặn: Git không tạo được
`.git/index.lock` (Read-only file system). Không có commit mới; HEAD vẫn là
`d9d3e14`. Các file liên quan còn ở working tree, chưa stage. Cần môi trường
cho phép ghi cache SDK và metadata Git để chạy đủ kiểm chứng và commit.
Token Codex: không đo được từ CLI/tool output trong phiên.
