# Bước B — dừng tại blocker Application lifecycle

Ngày: 2026-11-13 UTC. Branch `rdp-prototype`, đầu vào HEAD `8417702`.
**Chưa triển khai bước B.** Chỉ thêm tài liệu này theo điều kiện dừng của yêu cầu;
không sửa manifest, Kotlin, Dart, agent-mode v1.4 hay source FreeRDP.

## Bằng chứng và quyết định dừng

Đã đọc `docs/rdp-step11-api-map.md` và đối chiếu source thật. Quy ước:

- `J/`: `/home/hatch/workspace/FreeRDP-3.33.0/client/Android/Studio/freeRDPCore/src/main/java/com/freerdp/freerdpcore/`.
- `M/`: `/home/hatch/workspace/FreeRDP-3.33.0/client/Android/Studio/`.
- `F/`: `/home/hatch/workspace/flutter-3.50.0/engine/src/flutter/shell/platform/android/io/flutter/`.

`GlobalApp.sessionMap` là **private static** (`J/application/GlobalApp.java:43`).
Tìm phép gán `sessionMap =` trong class chỉ có một kết quả tại dòng 145, trong
`onCreate`. `createSession` ghi trực tiếp vào map (:103–115), `getSession` gọi
map.get mà không kiểm tra null (:117–120). `setEventListener` không khởi tạo map.
Subclass không thể gán field private một cách hợp lệ; không có public initializer
cho registry. Không thử reflection, JNI riêng hoặc gọi lifecycle bằng tay.

Gọi `super.onCreate()` sẽ luôn chạy các tác dụng phụ sau, trước khi biết Dart có
chọn RDP mode hay không (`J/application/GlobalApp.java:137–158`):

| Tác dụng phụ | Bằng chứng source | Ảnh hưởng/rủi ro cho agent-mode |
|---|---|---|
| Khởi tạo preferences | `J/presentation/ApplicationSettingsActivity.java:217–240` | Nạp 5 XML defaults, ghi client name ngẫu nhiên vào SharedPreferences; không chỉ khởi tạo registry. Đường này không mở Room/SQLCipher theo source đã đọc. |
| Đặt night mode | `GlobalApp.java:143`; `ApplicationSettingsActivity.java:330–345` | Đặt AppCompat default toàn tiến trình, mặc định follow system; MainActivity hiện extends FlutterFragmentActivity. |
| Bật print file observer | `GlobalApp.java:149–150`; `J/presentation/PrintJobMonitor.java:30–48` | Theo dõi `/sdcard/Download`, callback cho `rdp_print_*.pdf` ngay cả khi không có session RDP. |
| Đăng ký screen receiver | `GlobalApp.java:154–158`; `J/application/ScreenReceiver.java:25–34` | Thêm xử lý screen on/off và timer dùng preferences (:80–99 của GlobalApp), không có điều kiện RDP mode. |

Rủi ro print có đường source cụ thể: callback gọi
`PrintNotificationHelper.notify` (`GlobalApp.java:149`), helper dùng authority cố
định `com.freerdp.afreerdp.fileprovider` (`J/presentation/PrintNotificationHelper.java:32,46–50`).
Provider đó được khai báo trong **app mẫu** (`M/aFreeRDP/src/main/AndroidManifest.xml:97–105`),
không phải provider clipboard trong core (`M/freeRDPCore/src/main/AndroidManifest.xml:110–115`),
và manifest Ace hiện không khai báo provider này. Chưa khẳng định crash thực tế:
khả năng observer đọc được thư mục phụ thuộc Android/storage policy. Nhưng đây là
đường phụ thuộc app mẫu và hành vi nền ngoài yêu cầu, có bằng chứng source.

Vì yêu cầu đòi chỉ khởi tạo registry, không đổi hành vi agent-mode và yêu cầu
**DỪNG** nếu không thể khởi tạo registry hợp lệ khi cần tách onCreate, không dùng
GlobalApp nguyên trạng và không viết subclass giả vờ tối thiểu. Cần một thay đổi
upstream/AAR có API khởi tạo registry/listener riêng (và cập nhật bản đồ API),
hoặc thay đổi rõ ràng ràng buộc lifecycle trước khi tiếp tục. Chưa sửa workflow
để patch thư viện vì scope hiện chỉ cho phép API public đã lập bản đồ.

## Flutter embedding đã đối chiếu

FlutterApplication của SDK 3.50.0 chỉ là class rỗng extends Application
(`F/app/FlutterApplication.java:9–18`). Delegate tạo engine qua FlutterEngineGroup
(`F/embedding/android/FlutterActivityAndFragmentDelegate.java:308–345`);
FlutterEngine gọi `startInitialization` và `ensureInitializationComplete`
(`F/embedding/engine/FlutterEngine.java:387–390`). MainActivity hiện dùng
FlutterFragmentActivity, đăng ký plugin trong configureFlutterEngine.
Theo source, embedding v2 không cần Application kế thừa FlutterApplication để
khởi tạo loader/engine. Đây không phải blocker phát hiện được; chưa có kiểm chứng
APK với Application thay thế vì đã dừng trước sửa code.

## Phần chưa triển khai và đường API dự kiến

Không có API FreeRDP mới được gọi trong commit này. Session lifecycle, form,
renderer, trạng thái và teardown vẫn chưa triển khai. Màn hình chờ 50/50 và
AbsorbPointer hiện tại giữ nguyên. Các bước dưới đây là thiết kế chờ giải quyết
blocker, không phải mô tả code đã chạy:

1. Form chỉ RDP mode giữ credentials trong RAM, host `100.101.127.41`, port
   `3389`; không persist/log password, clear controller và bỏ references khi
   ngắt/dispose. Kết nối lại phải nhập lại password đã xóa.
2. Tạo BookmarkBase TYPE_MANUAL; setters host/port/user/domain/password
   (`J/domain/BookmarkBase.java:143–152,182–242`), size bằng SurfaceView pixel thật,
   colors 32 (:663–688,744–766), security 3 (:1087).
   `GlobalApp.createSession` (:103–108), `SessionState.setUIEventListener`
   (`J/application/SessionState.java:102–104`), kiểm tra handle và boolean
   `LibFreeRDP.setConnectionInfo` (`J/services/LibFreeRDP.java:257–495`) rồi mới
   `connect` (:214–224). Bookmark wrapper tự thêm `/cert:ignore` (:491): phải ghi
   nhận chính sách này khi triển khai.
3. Mẫu dùng ConnectThread (`J/presentation/SessionActivity.java:613–644`), native
   connect tạo worker (`client/Android/Studio/freeRDPCore/src/main/cpp/android_freerdp.c:970–989`).
   Dự kiến chạy cấu hình/connect trên executor để tránh chặn UI; chưa chốt code
   đồng bộ executor/teardown khi lifecycle chưa được giải quyết.
4. Implement đủ EventListener/UIEventListener (:873–931 của LibFreeRDP).
   Auth điền StringBuilder user/domain/password; callback signature đã ghi trong
   api-map. Post thao tác View/Bitmap lên main. Settings/resize tạo bitmap theo
   width/height/bpp; updateGraphics (:564–569) copy dirty rect, Canvas của
   SurfaceHolder vẽ vừa khung, giữ tỉ lệ và nền đen. Surface thay đổi chỉ scale,
   chưa gửi monitor layout (bước C). Cần bảo vệ handle/bitmap trước callbacks trễ.
5. Trạng thái tới Dart qua MethodChannel mở rộng. `connect=true` chỉ là bắt đầu
   worker. Theo dõi auth callback để mô tả failure có/không đi qua auth; không
   khẳng định failure trước auth chắc chắn do mạng, hoặc failure sau auth chắc
   chắn sai password. `freerdp_get_last_error_string` private (:179), không có
   public wrapper để lấy nguyên nhân chính xác.
6. Dispose bỏ listener, cancel khi connecting (:238–241), disconnect khi connected
   (:226–236); lịch freeSession (:128–135 của GlobalApp) sau callback trả về.
   Không free đồng bộ trong callback: LibFreeRDP cập nhật state sau listener
   (:605–648), freeInstance có wait (:191–212). Race giữa callback cuối và native
   worker thoát vẫn cần xử lý/kiểm chứng; chưa tuyên bố có teardown an toàn.

## Kiểm chứng VM

Chỉ dùng `/home/hatch/workspace/flutter-3.50.0/bin/flutter`:

| Lệnh | Kết quả |
|---|---|
| `flutter pub get` | Exit 0, Got dependencies. |
| `flutter analyze` | Exit 0, No issues found, 0 issue. |
| `flutter test` | Exit 0, 30 pass, 0 fail. |

Lần pub get đầu trong sandbox lỗi ghi cache SDK read-only; chạy lại với quyền
ghi cache SDK đã thành công. Analyze/test cũng dùng quyền đó. Test có warning
tap miss trong widget tests hiện có; không có test fail. Test RDP hiện có vẫn
pass, kiểm tra hai nửa bằng nhau và không gọi HTTP agent. Không thêm test form
vì form chưa triển khai. Không chạy Gradle, không build APK, không copy SDK.
AAR không có trên VM; **chưa kiểm chứng Kotlin/FreeRDP compile**. Dart pass không
chứng minh lifecycle Android hay kết nối thật.

## CI và Fold6 sau khi giải quyết blocker

Chưa push, chưa kích hoạt CI, chưa đụng PC của An, chưa yêu cầu credentials.
Commit tài liệu này không biến APK màn hình chờ thành client RDP.

Sau khi triển khai được bước B, CI cần build lại AAR 3.33.0 và APK arm64 để xác
nhận Kotlin/API/resources/manifest compile. Build thành công không chứng minh NLA.
Trên Fold6 của An mới kiểm chứng đăng nhập NLA thật tới `100.101.127.41:3389`,
framebuffer/dirty updates, trạng thái lỗi, ngắt khi connecting/connected, kết nối
lại, dispose và surface destroy/recreate. Đồng thời chạy agent-mode để kiểm tra
không đổi startup/theme/HTTP/input behavior. Không coi các kiểm chứng tương lai
này là đã pass. Rủi ro còn lại: policy auth/certificate, timing callback/native
worker, bitmap/surface lifecycle, và tương thích artifact AAR với source.

Tổng token: không đo được.
