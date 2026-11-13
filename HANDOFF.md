# Bàn giao Ace Remote v1 cho Muse

Project: `/home/hatch/workspace/ace-remote/app`. Android ID/namespace `vn.aceremote.app`, tên hiển thị Ace Remote, version `1.0.0+1`, Android tối thiểu API 23. Không sửa/copy lên PC, không tạo repo/commit/push, không build release hay cấu hình ký release. APK debug do Android toolchain ký debug tự động nếu build được; không tạo keystore riêng.

## Đã triển khai

- Thẻ Windows ace và MacBook vô hiệu hóa. `/health` kiểm tra trạng thái, nút Thử lại, Base URL chỉnh/lưu được. Xử lý timeout 6 giây, HTTP lỗi, 401/403, ảnh lỗi; không để màn hình trắng.
- Poll ảnh tuần tự, 500/1000 ms nghỉ giữa các lần lấy ảnh, giảm tốc theo thời gian đáp ứng hoặc lỗi (tối đa 8 giây); dừng nền và khi thoát remote. Ảnh cũ giữ lại có báo lỗi. Pinch, pan vùng zoom, vừa màn hình/1:1. 1:1 dùng pixel ảnh, còn Android có device pixel ratio riêng.
- Chạm tuyệt đối ánh xạ theo ảnh đã fit/zoom và origin/size do agent cung cấp, clamp ở mép, hỗ trợ x âm. Chặn click tuyệt đối nếu thiếu metadata. Không đoán ảnh là màn chính khi agent có thể trả cả desktop.
- Trackpad: vuốt, chạm trái, chạm 2 ngón phải, 2 ngón cuộn, giữ 500 ms để kéo. Kéo cần capability `mouse_drag`. Nút Click Phải luôn hiện bên phải vùng điều khiển. Di chuột tương đối cần `relative_move`, hoặc mô phỏng qua con trỏ tuyệt đối khi có metadata. Con trỏ mô phỏng không đồng bộ với chuột vật lý PC.
- Layout ngang nửa trên ảnh, nửa dưới trackpad trái/bàn phím phải; dọc ảnh chiếm vùng còn lại, lớp trackpad trong suốt bật/tắt và bàn phím kéo lên bằng icon. Xoay không tạo lại kết nối, không reset con trỏ. Bàn phím hệ thống chỉ mở khi chạm ô nhập text, vùng ảnh co lại qua adjustResize.
- QWERTY, số, phím điều hướng/modifier; ô nhập dùng IME tiếng Việt Android. Gõ và Dán đều gửi `/type` sau escape SendKeys. Dán lấy clipboard điện thoại theo thao tác người dùng, không đồng bộ tự động. Dán trên PC trong hàng phím tắt gửi Ctrl+V (clipboard PC), là thao tác khác.
- Phím tắt, khóa máy, quản lý tác vụ; Ctrl+Alt+Del chỉ gửi nếu agent công bố `sas`, nếu không thông báo rõ Windows SendKeys không làm được SAS.
- Ngủ, khởi động lại, tắt máy. Hai hộp xác nhận riêng cho restart/shutdown. Ưu tiên `/power` nếu agent công bố; fallback qua Win+R → `/type` lệnh `shutdown /s /t 0` hoặc `shutdown /r /t 0` → Enter. Có nghỉ 650 ms sau Win+R. Không bảo đảm focus Windows, nên UI ghi rõ trước xác nhận và chỉ nói đã gửi yêu cầu, không báo Windows đã thực thi. Ngủ fallback `/key` với `Sleep`, cần agent ánh xạ VK_SLEEP. Không đánh thức máy ngủ.
- Giao diện theo palette Thuốc Vui đọc từ project có sẵn: teal `#2BB3A3`, sáng nền kem/thanh vàng, tối xanh đen; Theo điện thoại mặc định, Sáng/Tối ghi đè hệ thống.
- PIN 4–6 số nhập lại lần đầu; hash SHA-256 lặp 60.000 vòng với salt ngẫu nhiên 32 byte, hash/salt lưu qua flutter_secure_storage (Android Keystore), không lưu PIN plaintext. Hạn chế nhập sai từ lần 5 bằng khoảng chờ 30 giây (trong tiến trình). Vân tay dùng local_auth với biometricOnly; lỗi/không có sinh trắc học dùng PIN. Tự khóa sau 5 phút không có pointer activity, cả khi trở lại từ nền. Remote bị pop khỏi navigation khi khóa, bỏ lệnh chờ của phiên cũ. Cố gắng nhả kéo khi nền/thoát; agent vẫn cần watchdog nhả chuột khi client rớt mạng.
- SharedPreferences chỉ lưu Base URL, theme, poll bằng các Dart key `ace_remote_v1_base_url`, `ace_remote_v1_theme`, `ace_remote_v1_poll_ms`. Native legacy tương ứng `flutter.ace_remote_v1_*`; không có code native tự đọc prefs. Không lưu mật khẩu Windows, clipboard hay log lệnh thật. Android backup tắt để tránh restore secret không còn key.

## Agent PC cần đối chiếu/bổ sung — từng mục

Brief không có source agent hay schema payload. Đây là **hợp đồng client đề xuất**, chưa được xác nhận với agent.exe. Mọi thao tác thật cần Muse kiểm tra sau review, không được xem HTTP 200 là bằng chứng Windows thực hiện đúng.

1. **Binding Tailscale:** agent hiện nghe `127.0.0.1:8765`. PC cần bind `100.101.127.41:8765` (ưu tiên) hoặc `0.0.0.0:8765` kèm firewall chỉ cho tailnet. Chạy GUI agent trong phiên An, không PsExec. App mặc định `http://100.101.127.41:8765`, đổi trong Cài đặt và Kiểm tra kết nối. App không thiết lập tunnel, không đổi binding/firewall.
2. **Chọn màn hình + geometry:** `GET /health` trả metadata dưới đây. `GET /screenshot?monitor=1|2` trả PNG/JPEG **riêng màn hình đó**, không crop/rotate/letterbox bên trong ảnh. Chỉ công bố `select_monitor` khi đã hỗ trợ thực sự. ID 1 chính (0,0,1920,1080), ID 2 phụ (-1920,0,1536,864), cần đo lại từ OS, kể cả y và DPI. Tọa độ `/click` và `/move` phải cùng không gian pixel desktop Windows; xử lý DPI awareness. Nếu legacy `/health` chỉ trả text thì trạng thái online vẫn hoạt động, nhưng app không giả vờ có metadata/chọn màn hình.
3. **Tắt/khởi động lại/ngủ:** bổ sung `POST /power` JSON `{"action":"shutdown|restart|sleep","monitor":1}` và capability `power`. Cần thực thi ở phiên có quyền phù hợp, trả lỗi thật khi không làm được. Fallback Run/shutdown hiện có nhưng chưa xác nhận PC thật; focus bị đổi hoặc agent không hỗ trợ Win+R có thể không chạy. Sleep fallback cần ánh xạ phím Sleep. Không có Wake-on-LAN.
4. **Chuột:** `POST /click` JSON `{"button":"left|right","x":-1152,"y":432,"monitor":2}` (x/y có thể vắng: click vị trí hiện tại). Kéo gửi cùng endpoint với `action:down|up`, chỉ bật `mouse_drag` khi hỗ trợ. `POST /move` nhận x/y tuyệt đối; hoặc `{"relative":true,"dx":10,"dy":-4,"monitor":1}` nếu capability `relative_move`. `POST /scroll` nhận `{"delta":120,"monitor":1}` theo wheel Windows. Xác minh dấu/đơn vị. Nên tự nhả nút khi timeout/disconnect, vì client không thể bảo đảm up đến PC lúc rớt mạng.
5. **Bàn phím/tiếng Việt:** `POST /key` nhận `{"key":"Ctrl+C","monitor":1}` (tên semantic Win+L, Alt+Tab, Left, Backspace, PrintScreen, Sleep...). Agent phải dịch sang SendKeys/VK tương ứng; không đưa nguyên chuỗi `Ctrl+C` vào SendKeys. `/type` nhận `{"text":"Việt {+}{^}{%}{~}{(}{)}{{}{}}","monitor":1}`; client **đã escape** literal `+ ^ % ~ ( ) { }`. Tránh escape lần hai. Giữ Unicode; cần kiểm chứng IME/ô chat. Không có endpoint paste trong brief nên nút Dán điện thoại vẫn dùng `/type`; nếu ô chat không nhận, PC nên bổ sung paste Unicode qua clipboard PC + Ctrl+V và cập nhật adapter client sau khi chốt schema. Không có auto clipboard sync.
6. **SAS/khóa/quyền:** Win+L/Ctrl+Shift+Esc được gửi qua `/key`. Ctrl+Alt+Del cần cơ chế Windows SAS riêng, capability `sas`; SendKeys thông thường không làm được. Không bật capability khi chưa có triển khai.
7. **Phản hồi lỗi:** endpoint điều khiển dùng POST JSON UTF-8, screenshot GET binary, health GET. Trả HTTP 2xx khi chấp nhận, 401/403 hết phiên/không quyền, 4xx/5xx lỗi. Chưa có schema auth/token trong brief; không lưu secret/hardcode token. Phạm vi truy cập cần giới hạn bằng Tailscale/ACL phía PC.

Ví dụ `/health` đề xuất:

```json
{
  "capabilities": ["select_monitor", "relative_move", "mouse_drag", "power"],
  "monitors": [
    {"id":1,"x":0,"y":0,"width":1920,"height":1080},
    {"id":2,"x":-1920,"y":0,"width":1536,"height":864}
  ]
}
```

## Mock và kiểm tra bằng tay (chưa thực hiện trên Android/PC thật)

```sh
flutter run --dart-define=ACE_MOCK=true
# Quay lại agent thật:
flutter run --dart-define=ACE_MOCK=false
```

Mock tạo ảnh có lưới, số màn hình, timestamp; health thành công và log lệnh. Không có cờ bỏ qua PIN. Mở icon nhật ký trên remote để xem JSON. Muốn kiểm tra lỗi mạng, chạy bản không mock với URL loopback không có server, không cần gọi PC.

| Luồng | Cách kiểm tra / kết quả cần thấy |
|---|---|
| Health OK/lỗi | Mock thẻ Trực tuyến; bản thật URL port đóng → lỗi tiếng Việt, Thử lại; Cài đặt có Kiểm tra kết nối. HTTP 401 được test bằng server cục bộ. |
| Chạm tuyệt đối | Mock tắt lớp trackpad, chạm giữa màn 1 → (960,540); màn 2 → (-1152,432); thử góc/mép sau zoom/pan, phải giữ mapping. |
| Click Phải | Bấm nút lớn và chạm hai ngón: log `/click` button right. |
| Chọn màn hình | Mock đổi số trên ảnh và monitor trong log; agent không capability phải thông báo Chưa chuyển. Trên PC phải đối chiếu nội dung từng màn hình thực. |
| Copy/Paste/Win+L | Kiểm tra `/key` Ctrl+C, Ctrl+V, Win+L. Clipboard điện thoại chứa `Tiếng Việt +^%~(){}` → `/type` escaped chính xác. Chỉ thử Win+L trên PC khi sẵn sàng mở khóa lại. |
| Tắt máy | Lần 1, lần 2; Hủy bất kỳ bước nào không có lệnh power. Mock chấp thuận cả 2 → `/power` shutdown. PC legacy → chuỗi Run/shutdown, chưa xác minh. |
| PIN 5 phút | Đặt PIN, nhập sai rồi đúng; để yên ≥5 phút trong remote/cài đặt và cả khi nền → về màn khóa, không gửi thêm lệnh chờ. Sinh trắc học cần điện thoại có đăng ký vân tay. |
| Xoay/layout | Xoay ngang/dọc, thử máy gập, bàn phím không che ảnh, vị trí chuột không reset; thử kéo rồi nền/thoát để kiểm tra nhả nút. |
| Mạng chậm | Server ảnh trả chậm/lỗi liên tiếp → poll giảm, không chồng screenshot, có lỗi/Thử lại. |

Các test tự động không thay thế kiểm thử điện thoại thật, vân tay/Keystore, foldable, Windows input, DPI hoặc Tailscale.

## Bằng chứng chạy trên VM (13/11/2026)

- `flutter pub get`: exit 0, Got dependencies; [log](verification/pub-get.log).
- `flutter analyze`: kết quả cuối trong [log](verification/analyze.log).
- `flutter test --reporter expanded`: kết quả cuối trong [log](verification/test.log). Các test gồm SendKeys/Unicode, tọa độ màn phụ và clamp, Base URL, mock log, HTTP thật với server loopback (health/JSON/screenshot query/401), trackpad đa ngón/kéo, hai xác nhận tắt máy và hủy, PIN/hash/idle lock.
- `flutter build apk --debug`: chưa build được; thử JDK17/Android SDK có sẵn và cấu hình tắt daemon, đều vướng kết nối daemon/worker trên VM. Lần cuối `:gradle:compileGroovy` → `Unable to connect to the child process 'Gradle Worker Daemon 1'`, timeout 120 giây, exit 1. [Trích lỗi và các lệnh](verification/build-debug.log). Không có APK để bàn giao; chưa xác nhận native Android compile/runtime.
- Không có emulator/điện thoại được dùng. Không kết nối hay gửi lệnh tới PC ace. Không tuyên bố đã kiểm tra Windows input, switch monitor thật, shutdown/restart thật, Tailscale, vân tay thật hay Keystore thật.
