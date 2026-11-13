# Bước C — resolution theo nửa trên

Ngày 2026-11-13 UTC. Branch `rdp-prototype`, HEAD đầu vào `ff4c4be`.
Đã đọc step11–14, Kotlin/Dart/main và đối chiếu source FreeRDP 3.33.0 local.

## Nguồn kích thước và cấu hình trước connect

Chọn Kotlin lấy `width/height` từ `SurfaceHolder.Callback.surfaceChanged` của
SurfaceView nằm trong nửa trên. Đây là pixel của surface thực, đã gồm density;
không nhân devicePixelRatio, không dùng logical pixel hay toàn màn hình.
`status.widthPx/heightPx` dùng cùng dữ liệu này, trả 0 khi surface bị destroy.
Không thêm kích thước vào payload Dart: đọc ngay dưới lock trên executor trước
khi tạo Bookmark tránh vòng status → Dart → connect mang số đo cũ. Nếu surface
đổi sau đó, callback resize sẽ cập nhật phiên. Không đọc View.width trên worker.

Mỗi chiều hợp lệ trong 1..65536; chiều sai hoặc surface chưa ready fallback
1024 (width), 768 (height), tương ứng validator upstream. Gọi
`getScreenSettings().setResolution("custom", width, height)` trước
`setConnectionInfo`; giữ TYPE_MANUAL, colors=32, security=3 NLA và executor B2.
Bookmark chỉ áp dụng resolution khi cấu hình phiên mới.

Gốc `J/` = `/home/hatch/workspace/FreeRDP-3.33.0/client/Android/Studio/freeRDPCore/src/main/java/com/freerdp/freerdpcore/`.
Gốc `C/` = `/home/hatch/workspace/FreeRDP-3.33.0/client/Android/Studio/freeRDPCore/src/main/cpp/`.

| API/đường source | Dòng | Ý nghĩa |
| --- | --- | --- |
| J/domain/BookmarkBase.java, ScreenSettings.setResolution(String,int,int) | 663–688 | public setter custom |
| J/domain/BookmarkBase.java, validate/getWidth/getHeight/setWidth/setHeight | 625–648,738–757 | Getter validate chiều <=0 hoặc >65536 về 1024/768 |
| J/services/LibFreeRDP.java, setConnectionInfo | 330–331 | Chuyển getter thành `/size:WxH` |
| J/services/LibFreeRDP.java | 433–434 | Bookmark wrapper thêm `/disp` |
| J/services/LibFreeRDP.java, sendMonitorLayout(long,int,int) | 600–603 | public boolean wrapper |
| C/android_freerdp.c | 1251–1264 | JNI gửi monitor layout |
| C/android_disp.c | 54–93 | false khi thiếu DISP/SendMonitorLayout hoặc send lỗi; true khi submit thành công |
| J/presentation/SessionActivity.java | 389–411 | Mẫu gửi layout sau config/layout thay đổi |

Không thêm JNI/reflection/API private hoặc sửa FreeRDP.

## Resize, xoay và surface lifecycle

Debounce callback 250ms, bỏ số đo không hợp lệ; chỉ gửi khi connected và khác
kích thước đã yêu cầu. Nếu resize khi đang connecting, OnConnectionSuccess lên
lịch kiểm tra kích thước mới nhất. Gửi trên executor cũ, dưới cùng lock bảo vệ
handle/session; generation bỏ tác vụ lỗi thời khi đổi size, destroy hoặc stop.

Ưu tiên `LibFreeRDP.sendMonitorLayout`. Nếu false (có thể DISP chưa ready), thử
lại mỗi 500ms, tối đa 10 lần cho mỗi generation. Nếu true, chờ tối đa 3 giây
kiểm tra bitmap có đúng kích thước qua OnGraphicsResize/OnSettingsChanged;
true chỉ xác nhận submit, không chứng minh server chấp nhận. Nếu hết retry hoặc
bitmap vẫn sai, dùng stop/cleanup B2, sau cleanup hiển thị failed và yêu cầu
nhập lại mật khẩu, bấm Kết nối lại. Phiên mới đọc lại kích thước surface.
Đây là reconnect **thủ công**, không tự lưu lại credentials đã xóa của B2.
Không giữ phiên sai kích thước vô hạn khi DISP không dùng được.

Surface destroy đặt ready=false, xóa số đo, vô hiệu công việc resize cũ; recreate
nhận số đo mới từ surfaceChanged, vẽ lại bitmap và đồng bộ resolution nếu cần.
Retry/watchdog đều kiểm tra disposed/stopping/terminal/attempt/generation trước
khi gọi native; không free handle trực tiếp từ resize. Nếu Activity/PlatformView
bị hủy hoàn toàn thì theo dispose B2, phiên mới cần người dùng kết nối lại.
Không bảo đảm lifecycle native khi upstream không phát callback cuối (giới hạn B2).

Canvas vẫn giữ tỉ lệ trong lúc chờ remote resize. Khi framebuffer đúng size,
ảnh lấp đầy vùng surface, không stretch/crop. Server có thể từ chối/clamp kích
thước, giới hạn protocol/server có thể hẹp hơn validator 65536; timeout 3 giây
là chính sách app, có thể yêu cầu reconnect trên server chậm. Không bảo đảm mọi
server chấp nhận mọi số pixel. Không làm input bước D. Main/Dart layout không
đổi: 50/50, AbsorbPointer và ACE_RDP=true giữ nguyên; agent-mode không sửa.

## Kiểm chứng VM và giới hạn

Chỉ dùng `/home/hatch/workspace/flutter-3.50.0/bin/flutter`:

- `flutter pub get`: exit 0, Got dependencies. Lần đầu sandbox không ghi được
  cache SDK; chạy lại với quyền ghi cache thành công. Không copy SDK sang /tmp.
- `flutter analyze`: exit 0, No issues found (0 issue).
- `flutter test`: exit 0, 32 pass, 0 fail. Có warning hit-test ở test cũ.
- Thêm widget test mock status: giữ nguyên pixel native ở density=2 và đọc số
  đo sau resize. Các test 50/50, không HTTP agent và form/lifecycle cũ vẫn pass.
  Vì chọn lấy kích thước trực tiếp Kotlin, test không giả vờ chứng minh payload
  resolution Dart hay đo surface Android; không có native trong widget test.
- `git diff --check`: sạch.

Kotlin compile với AAR thật cần CI; resolution, DISP, xoay/Fold6, surface
recreate và framebuffer thật cần kiểm chứng trên Fold6 của An. VM không có AAR
thật, không compile Kotlin với stub; không khẳng định đã chạy RDP hay đạt màn
hình không viền trên thiết bị. Chưa chạy CI, Gradle hay build APK, không push,
không đụng PC của An. Chính sách certificate và các giới hạn B2 giữ nguyên.
