# Bước B2 — lifecycle, connect và framebuffer

Ngày 2026-11-13 UTC. Branch `rdp-prototype`, nền `5ad92b5`. Đối chiếu API-map bước 11 với source FreeRDP 3.33.0 local; không chạy Gradle hoặc build APK, không truy cập PC của An, không push.

## API và nguồn đã đối chiếu

Gốc `J` = `/home/hatch/workspace/FreeRDP-3.33.0/client/Android/Studio/freeRDPCore/src/main/java/com/freerdp/freerdpcore/`.
Gốc `U` = `/home/hatch/workspace/FreeRDP-3.33.0/`.

| API public dùng | Source (dòng) | Vai trò |
| --- | --- | --- |
| `LibFreeRDP.hasH264Support()` | J/services/LibFreeRDP.java:126 | Thăm dò thư viện, bắt LinkageError/RuntimeException |
| `BookmarkBase.TYPE_MANUAL`, setters host/port/user/domain/password | J/domain/BookmarkBase.java:77; J/services/LibFreeRDP.java:275–328 | Bookmark RAM, không gọi persistence |
| `getScreenSettings().setColors(32)`, `getAdvancedSettings().setSecurity(3)` | J/domain/BookmarkBase.java:207,766,1087; J/services/LibFreeRDP.java:333,358–362 | 32 bpp, NLA |
| `GlobalApp.createSession(BookmarkBase, Context)` | J/application/GlobalApp.java:103–108 | newInstance và đăng ký SessionState |
| `SessionState.getInstance/setUIEventListener/setSurface` | J/application/SessionState.java:82,102–114 | Handle, callback, BitmapDrawable; setter listener chỉ gán field, nhận null được |
| `LibFreeRDP.setEventListener(EventListener)` | J/services/LibFreeRDP.java:181–184; J/application/GlobalApp.java:40,136–158 | Một listener toàn process, GlobalApp đăng ký trong onCreate dòng 147 |
| `LibFreeRDP.setConnectionInfo(Context,long,BookmarkBase)` | J/services/LibFreeRDP.java:257–495 | Parse cấu hình bằng wrapper public |
| `LibFreeRDP.connect/disconnect/cancelConnection` | J/services/LibFreeRDP.java:214–241 | Khởi động, ngắt phiên connected, hủy connecting |
| `EventListener`, `UIEventListener` | J/services/LibFreeRDP.java:873–931 | Đã đối chiếu đầy đủ signature, kể cả tên `OnVerifiyCertificateEx` viết sai chính tả từ upstream |
| Callback lifecycle và routing UI | J/services/LibFreeRDP.java:605–648,650–743 | Listener lifecycle được gọi trước cập nhật mInstanceState; UI callback tra SessionState |
| `LibFreeRDP.updateGraphics(long,Bitmap,int,int,int,int)` | J/services/LibFreeRDP.java:564 | Copy dirty rectangle vào bitmap |
| `GlobalApp.freeSession(long)` / `LibFreeRDP.freeInstance(long)` | J/application/GlobalApp.java:130–137; J/services/LibFreeRDP.java:191–212 | Gỡ map và giải phóng; có thể chờ wrapper state |

Không gọi native private, reflection hoặc JNI tự viết. `freerdp_get_last_error_string` ở J/services/LibFreeRDP.java:179 là **private**, không có public wrapper để dùng trong bước này.

## Luồng kết nối và trạng thái

`ACE_RDP=true` mới vào nhánh RDP. Main chỉ thay widget ở nửa remote bằng `RdpConnectionPane`; Column hai Expanded 50/50 và key `remote-half`/`keyboard-half` giữ nguyên. Pane sở hữu form và Stack chứa RdpSurface. Agent-mode v1.4 không đổi. Non-Android vẫn hiển thị “RDP chỉ hỗ trợ Android”; gửi connect không có native channel sẽ báo lỗi cục bộ.

RdpSurface là StatefulWidget, RdpController cung cấp connect/disconnect/status, đăng ký nhận method `state` từ native trên `vn.aceremote.app/rdp/<viewId>`, tháo handler khi dispose. ViewType vẫn `vn.aceremote.app/rdp`.

Chỉ tạo native session **khi bấm Kết nối**, không tạo khi mount PlatformView: tránh cấp tài nguyên/kết nối khi chưa có thông tin đăng nhập. Validate host, port 1–65535, username và password; chuyển idle → connecting trước khi executor tạo Bookmark, SessionState, gắn listener, setConnectionInfo rồi connect. Một attempt tại một thời điểm; chỉ cho retry sau khi attempt cũ đã được free. Host mặc định 100.101.127.41, port 3389; không có tài khoản hardcode.

Event success chuyển connected và ẩn form, hiện chip “Đã kết nối” cùng nút ngắt. Connecting hiện “Đang kết nối…” và nút Ngắt. Ngắt chuyển **disconnecting** (“Đang ngắt kết nối…”), không báo disconnected sớm; failed/disconnected chỉ được phát sau khi tác vụ cleanup hoàn tất. Failure hiển thị lý do và nút Kết nối lại.

## Credentials và certificate

Password chỉ đi qua MethodChannel vào RAM Kotlin/native, không ghi SharedPreferences, keystore, file hay log. Dart xóa controller sau khi gửi yêu cầu, khi ngắt và dispose; retry phải nhập lại. Bookmark xóa password ngay sau setConnectionInfo (wrapper đã parse `/p:` vào native settings); bản RAM Attempt phục vụ OnAuthenticate được bỏ tham chiếu sau khi điền StringBuilder, hoặc khi success/stop/finish. Native giữ bản cần thiết đến khi giải phóng phiên. String bất biến và bản sao runtime không có bảo đảm zeroization; xóa controller/bỏ tham chiếu không đồng nghĩa xóa vật lý mọi byte RAM. Không có chức năng lưu bookmark trong plugin.

Bookmark wrapper **tự thêm `/cert:ignore`**, J/services/LibFreeRDP.java:491; do đó verify callback có thể không được gọi. Giữ cả hai verify callback trả **2** nếu attempt hợp lệ, 0 khi đang dừng: 2 chấp thuận **chỉ phiên này**, không lưu tin cậy như giá trị 1. Nguồn quy ước: U/include/freerdp/freerdp.h:244–245,291–292. Đây là chính sách certificate của prototype, chưa xác minh danh tính server; không được mô tả callback 2 như đã vô hiệu hóa `/cert:ignore`.

`authAttempted` chỉ đánh dấu đã vào callback OnAuthenticate của attempt. Không suy luận failure trước auth chắc chắn do mạng, hay sau auth chắc chắn sai password. Wrapper có thể dùng credentials đã parse mà không gọi callback. Message hiển thị có/chưa qua callback và “chưa xác định nguyên nhân”; lỗi tạo session/cấu hình/thư viện có thông báo riêng, không đưa exception chứa credentials ra UI.

## Rendering và teardown

OnSettingsChanged/OnGraphicsResize cấp bitmap và gắn BitmapDrawable vào SessionState. OnGraphicsUpdate gọi updateGraphics theo dirty rectangle. Yêu cầu render được gộp trên main Handler; snapshot bitmap được copy dưới lock, sau đó lockCanvas/draw/unlockCanvasAndPost **ngoài** lock lifecycle. Canvas nền đen và scale giữ tỉ lệ, không thay resolution theo nửa trên (bước C). Chưa làm input phím/chuột (bước D); bàn phím RDP vẫn AbsorbPointer.

RdpEvents multiplex theo handle và forward nguyên callback sang GlobalApp (GlobalApp dispatch listener Activity nếu có, J/application/GlobalApp.java:68–74,161–188). Cast applicationContext dùng `as?`; nếu không phải EventListener thì ném lỗi được start bắt và báo failed thay vì crash từ cast. Không có API getter listener, nên thiết kế dựa vào manifest GlobalApp và không có thành phần khác thay process listener sau install.

stop đánh dấu stopping, xóa credentials, bỏ UI listener, xóa framebuffer; executor gọi cancelConnection chỉ lúc connecting, disconnect khi connected. Nếu success đến trong lúc stopping/disposed, tác vụ success gọi disconnect. OnDisconnecting chỉ chuyển disconnecting; OnDisconnected/Failure gọi finish với guard terminal chống double cleanup. freeSession chạy trên executor, không gọi trực tiếp trong callback, không giữ lock trong lúc chờ freeInstance. Sau free mới xóa attempt và phát trạng thái cuối. dispose tháo channel/SurfaceHolder callback, không nhận thêm UI event; executor shutdown sau cleanup.

## Kiểm chứng VM và giới hạn

SDK duy nhất dùng: `/home/hatch/workspace/flutter-3.50.0/bin/flutter`.

- `flutter pub get`: thành công (exit 0); có thông báo phiên bản dependency mới, không nâng dependency.
- `flutter analyze`: **0 issue**, exit 0. Lần đầu thấy một unnecessary_import, đã bỏ và chạy lại sạch.
- `flutter test`: **31 pass, 0 fail**, exit 0. Có warning hit-test ở test menu/keyboard hiện hữu; không sửa agent-mode.
- Test RDP cũ giữ kiểm tra hai nửa bằng nhau và không gửi HTTP agent. Test mới mount RemotePage rdpMode=true, attach controller vào mock `vn.aceremote.app/rdp/0`, kiểm tra form/default host, payload connect, password rỗng sau gửi, event connecting/disconnecting/connected/failed, authAttempted true/false và method disconnect. Đây là mock transport, không kiểm chứng AndroidView/native.
- `git diff --check`: sạch.

**Blocker kiểm chứng native:** AAR không có trên VM. Đã đọc/đối chiếu Java source 3.33.0, SessionState, GlobalApp và API-map; không đoán signature và không compile Kotlin với stub để thay thế AAR. Kotlin compile với AAR thật, manifest merge chỉ kiểm chứng trên CI; kết nối RDP/rendering/lifecycle thật còn phải kiểm chứng trên Fold6 của An. Không khẳng định các phần này đã chạy thành công. Không chạy CI từ bước này.

Rủi ro cần kiểm chứng: timing callback native và cập nhật mInstanceState sau callback, cancel lúc success đua nhau, callbacks sau dispose, native không phát callback cuối có thể giữ disconnecting/tài nguyên (không tự free worker chưa dừng), process listener bị thành phần khác thay thế, memory/frame pacing của copy framebuffer và Canvas có thể block main thread dù không giữ lock lifecycle. Không thêm timeout/free cưỡng bức hay đổi thiết kế lớn khi chưa có bằng chứng runtime. Auto-reconnect của upstream phụ thuộc preferences; credentials không được giữ để tái xác thực tự động, reconnect cần nhập lại password. Các giới hạn này không được các widget test chứng minh.
