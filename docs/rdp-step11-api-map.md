# Bước A — Bản đồ API Android FreeRDP cho Ace Remote

Ngày: 2026-11-13 (UTC). FreeRDP: **3.33.0**; source local HEAD trùng tag `3.33.0`, working tree sạch khi kiểm tra. Repo app: branch `rdp-prototype`, HEAD `4963237`. Đây là khảo sát source, chưa build/chạy kết nối; chỉ tạo tài liệu này.

## Quy ước nguồn và kiểu

Mọi đường dẫn rút gọn bên dưới được ghép với thư mục gốc tuyệt đối sau (số sau dấu `:` là dòng source, khoảng dòng dùng để chỉ phần thân liên quan):

- `J/` = `/home/hatch/workspace/FreeRDP-3.33.0/client/Android/Studio/freeRDPCore/src/main/java/com/freerdp/freerdpcore/`.
- `C/` = `/home/hatch/workspace/FreeRDP-3.33.0/client/Android/Studio/freeRDPCore/src/main/cpp/`.
- `S/` = `/home/hatch/workspace/FreeRDP-3.33.0/client/Android/Studio/aFreeRDP/src/main/`.
- `U/` = `/home/hatch/workspace/FreeRDP-3.33.0/`.
- `A/` = `/home/hatch/workspace/ace-remote/app/`.

Kiểu ngắn trong signature là import Java chính xác: `Context` = `android.content.Context`, `Uri` = `android.net.Uri`, `Bitmap` = `android.graphics.Bitmap`, `BitmapDrawable` = `android.graphics.drawable.BitmapDrawable`, `KeyEvent` = `android.view.KeyEvent`, `Canvas` = `android.graphics.Canvas`, `String`/`StringBuilder` = `java.lang.String`/`java.lang.StringBuilder`; `BookmarkBase` = `com.freerdp.freerdpcore.domain.BookmarkBase`, `SessionState` = `com.freerdp.freerdpcore.application.SessionState`, `LibFreeRDP` = `com.freerdp.freerdpcore.services.LibFreeRDP`. Nguồn import: `J/services/LibFreeRDP.java:11–23`, `J/application/SessionState.java:11–21`, `J/utils/KeyboardMapper.java:11–17`, `J/presentation/SessionView.java:11–30`. Tên nested class ghi bằng dấu `.` trong Java; JNI dùng `$` nếu cần, nhưng các callback native ở đây đều ở class LibFreeRDP.

Hiện trạng app: chỉ đăng ký PlatformView, tạo SurfaceView và thăm dò H264, trả connected=false; chưa cấp phát session (`A/android/app/src/main/kotlin/vn/aceremote/app/RdpPlugin.kt:16–68`).

## (a) Tạo, giữ và giải phóng session

| Class đầy đủ | Signature | Nguồn | Hành vi |
|---|---|---|---|
| com.freerdp.freerdpcore.services.LibFreeRDP | `public static long newInstance(Context context)` | `J/services/LibFreeRDP.java:186–189`; `C/android_freerdp.c:797–889` | Context bất kỳ có getFilesDir hợp lệ; trả handle native freerdp* dưới dạng long; lỗi trả 0. Không đòi Activity. |
| com.freerdp.freerdpcore.services.LibFreeRDP | `public static void freeInstance(long inst)` | `J/services/LibFreeRDP.java:191–212`; `C/android_freerdp.c:892–898` | Nếu state connected thì disconnect rồi wait state bị xóa, sau đó free native context; có thể block. |
| com.freerdp.freerdpcore.application.GlobalApp | `public static SessionState createSession(BookmarkBase bookmark, Context context)` | `J/application/GlobalApp.java:103–108` | newInstance, new SessionState, đưa vào static sessionMap. |
| com.freerdp.freerdpcore.application.GlobalApp | `public static SessionState createSession(Uri openUri, Context context)` | `J/application/GlobalApp.java:110–115` | Tương tự với URI. |
| com.freerdp.freerdpcore.application.GlobalApp | `public static SessionState getSession(long instance)` | `J/application/GlobalApp.java:117–120` | Tra registry theo handle. |
| com.freerdp.freerdpcore.application.GlobalApp | `public static Collection<SessionState> getSessions()` | `J/application/GlobalApp.java:122–126` | java.util.Collection, trả bản sao values. |
| com.freerdp.freerdpcore.application.GlobalApp | `public static void freeSession(long instance)` | `J/application/GlobalApp.java:128–135` | Xóa registry rồi freeInstance. |
| com.freerdp.freerdpcore.application.SessionState | `public SessionState(long instance, BookmarkBase bookmark)` | `J/application/SessionState.java:53–59` | Giữ handle/bookmark trong instance. Constructor không tự đăng ký GlobalApp. |
| com.freerdp.freerdpcore.application.SessionState | `public SessionState(long instance, Uri openUri)` | `J/application/SessionState.java:61–67` | Giữ handle/URI trong instance. |
| com.freerdp.freerdpcore.application.SessionState | `public long getInstance()` | `J/application/SessionState.java:82–85` | Lấy handle. |
| com.freerdp.freerdpcore.application.GlobalApp | `public void onCreate()` | `J/application/GlobalApp.java:137–158` | Khởi tạo static synchronized sessionMap, đăng ký EventListener, preferences, print monitor, screen receiver. |

Handle native nằm trong `SessionState.private final long instance` (instance field), còn registry `GlobalApp.private static Map<Long,SessionState> sessionMap` là static; LibFreeRDP giữ static listener và private static LongSparseArray<Boolean> mInstanceState (`J/application/SessionState.java:37–41`; `J/application/GlobalApp.java:40–45,145–147`; `J/services/LibFreeRDP.java:34–38`). Native mỗi session có event_queue/thread trong androidContext (`C/android_freerdp.h:26–49`).

**Điều kiện dùng độc lập:** dùng public GlobalApp.createSession + SessionState.setUIEventListener; không cần mở SessionActivity. Nhưng phải để Android khởi tạo Application là GlobalApp hoặc subclass trước: registry chỉ được gán tại onCreate. Callback UI gọi GlobalApp.getSession; registry null có thể gây NullPointerException, registry thiếu handle thì render bị bỏ qua/auth=false (`J/application/GlobalApp.java:117–119,137–147`; `J/services/LibFreeRDP.java:650–681,726–744`). App mẫu khai báo `com.freerdp.afreerdp.application.GlobalApp` trong manifest, class này chỉ extends core GlobalApp (`S/AndroidManifest.xml:6–7`; `S/java/com/freerdp/afreerdp/application/GlobalApp.java:1–5`). Ace hiện dùng `${applicationName}` (`A/android/app/src/main/AndroidManifest.xml:4–9`); bước B cần tích hợp lifecycle này, không tự gọi new Application/onCreate bằng tay.

Luồng launcher mẫu còn có `com.freerdp.freerdpcore.services.SessionRequestHandlerActivity.public void onCreate(android.os.Bundle savedInstanceState)` chuyển intent SEARCH/VIEW/EDIT sang SessionActivity/BookmarkActivity; nó không sở hữu native session (`J/services/SessionRequestHandlerActivity.java:32–75`). `com.freerdp.freerdpcore.domain.ConnectionReference` chỉ tạo/giải mã chuỗi tham chiếu qua `public static String getBookmarkReference(long bookmarkId)`, `public static String getHostnameReference(String hostname)`, `public static String getFileReference(String uri)`, các predicate `public static boolean isBookmarkReference(String refStr)`, `isHostnameReference(String refStr)`, `isFileReference(String refStr)` và getter `public static long getBookmarkId(String refStr)`, `public static String getHostname(String refStr)`, `public static String getFile(String refStr)` (các predicate đều public static boolean; `J/domain/ConnectionReference.java:20,25,30,35,40,45,50,55,60`). Đây là tầng điều hướng app mẫu, không phải điều kiện để gọi public createSession (`J/application/GlobalApp.java:103–115`).

## (b) Tham số trước connect

Hai public entry point đều thuộc **com.freerdp.freerdpcore.services.LibFreeRDP**:

| Signature | Nguồn | Ý nghĩa |
|---|---|---|
| `public static boolean setConnectionInfo(Context context, long inst, BookmarkBase bookmark)` | `J/services/LibFreeRDP.java:257–495` | Tạo argv rồi parse; chỉ nhận bookmark TYPE_MANUAL, loại khác trả false (:275–278). |
| `public static boolean setConnectionInfo(Context context, long inst, Uri openUri)` | `J/services/LibFreeRDP.java:497–562` | Host/port từ URI, userInfo thành /u; query rỗng thành /key, +/- thành +/-key, còn lại /key:value. Cho phép đặt password, size, sec, authentication qua query. |

Không có public parseArguments; `private static native boolean freerdp_parse_arguments(long inst, String[] args)` tại `J/services/LibFreeRDP.java:152`. Không cần truy cập nó: cả hai public overload gọi sẵn (:494,:561); JNI parse argv qua freerdp_client_settings_parse_command_line (`C/android_freerdp.c:933–967`). Kiểm tra boolean trước connect; wrapper SessionState.connect mẫu bỏ qua boolean (`J/application/SessionState.java:69–79`).

### Setter cần cho phiên Windows/NLA

Tất cả setter dưới đây là public instance method, không tự lưu đĩa (thân setter chỉ gán field ở các dòng dẫn). Bookmark mặc định constructor public tại `J/domain/BookmarkBase.java:143–145`.

| Class đầy đủ | Signature | Nguồn | Ánh xạ argv |
|---|---|---|---|
| com.freerdp.freerdpcore.domain.BookmarkBase | `public void setType(int type)` | `J/domain/BookmarkBase.java:152`; `J/services/LibFreeRDP.java:275–278` | Chọn TYPE_MANUAL=1 (BookmarkBase:77). |
| com.freerdp.freerdpcore.domain.BookmarkBase | `public void setHostname(@NonNull String hostname)` | `J/domain/BookmarkBase.java:232`; `J/services/LibFreeRDP.java:280–284` | /v:hostname |
| com.freerdp.freerdpcore.domain.BookmarkBase | `public void setPort(int port)` | `J/domain/BookmarkBase.java:242`; `J/services/LibFreeRDP.java:280–284` | /port:port |
| com.freerdp.freerdpcore.domain.BookmarkBase | `public void setUsername(@NonNull String username)` | `J/domain/BookmarkBase.java:182`; `J/services/LibFreeRDP.java:314–318` | /u nếu không rỗng |
| com.freerdp.freerdpcore.domain.BookmarkBase | `public void setDomain(@NonNull String domain)` | `J/domain/BookmarkBase.java:202`; `J/services/LibFreeRDP.java:319–323` | /d nếu không rỗng |
| com.freerdp.freerdpcore.domain.BookmarkBase | `public void setPassword(@NonNull String password)` | `J/domain/BookmarkBase.java:192`; `J/services/LibFreeRDP.java:324–328` | /p nếu không rỗng |
| com.freerdp.freerdpcore.domain.BookmarkBase | `@NonNull public ScreenSettings getScreenSettings()` | `J/domain/BookmarkBase.java:207` | Lấy object cấu hình. |
| com.freerdp.freerdpcore.domain.BookmarkBase | `@NonNull public ScreenSettings getActiveScreenSettings()` | `J/domain/BookmarkBase.java:272–275` | Trả cùng screenSettings. |
| com.freerdp.freerdpcore.domain.BookmarkBase.ScreenSettings | `public void setResolution(@NonNull String resolution, int width, int height)` | `J/domain/BookmarkBase.java:663–688` | "custom" giữ width/height; "WxH" tự parse; automatic/fitscreen đặt 0. |
| com.freerdp.freerdpcore.domain.BookmarkBase.ScreenSettings | `public void setWidth(int width)`; `public void setHeight(int height)` | `J/domain/BookmarkBase.java:744,755`; `J/services/LibFreeRDP.java:330–331` | /size:WxH |
| com.freerdp.freerdpcore.domain.BookmarkBase.ScreenSettings | `public void setColors(int colors)` | `J/domain/BookmarkBase.java:766`; `J/services/LibFreeRDP.java:332` | /bpp |
| com.freerdp.freerdpcore.domain.BookmarkBase | `@NonNull public AdvancedSettings getAdvancedSettings()` | `J/domain/BookmarkBase.java:217` | Lấy cấu hình security. |
| com.freerdp.freerdpcore.domain.BookmarkBase.AdvancedSettings | `public void setSecurity(int security)` | `J/domain/BookmarkBase.java:1087`; `J/services/LibFreeRDP.java:358–371` | 3=NLA /sec:nla; 2=TLS; 1=RDP; default không ép. |

`@NonNull` là androidx.annotation.NonNull (`J/domain/BookmarkBase.java:17`). Screen getter validate kích thước: width/height <=0 hoặc >65536 đổi thành 1024/768; bpp không hợp lệ đổi 32 (`J/domain/BookmarkBase.java:625–648`). App mẫu tính screen metrics trước connect nếu automatic/fitscreen (`J/presentation/SessionActivity.java:553–571`).

**Bật/tắt authentication:** không có setter riêng trong BookmarkBase.AdvancedSettings (toàn bộ public setters ở :1001–1147). Public URI overload hỗ trợ `authentication=+` / `authentication=-` -> `+authentication` / `-authentication` và `sec=nla` -> `/sec:nla` (`J/services/LibFreeRDP.java:529–556`). Parser xác nhận bool authentication, default true (`U/client/common/cmdline.h:76–77`; `U/client/common/cmdline.c:5649–5652`). NLA force/toggle có mô tả chuẩn tại `U/client/common/cmdline.h:447–456`. Không nhầm bỏ authentication với đổi security protocol.

### Toàn bộ nhóm option nhánh Bookmark mẫu đặt trước connect

Các option bên dưới đều do `LibFreeRDP.setConnectionInfo(Context,long,BookmarkBase)` đặt; signature public là entry point ở trên. Bảng phụ lục setter/getter cuối tài liệu cho signature chính xác của model để điều chỉnh từng option.

| Option / điều kiện | Nguồn J/services/LibFreeRDP.java |
|---|---|
| argv[0]=LibFreeRDP, /gdi:sw, /client-hostname nếu preferences không rỗng | :266–273 |
| /v, /port; /tls:seclevel và enforce khi level>=0 | :280–312 |
| /u, /d, /p nếu không rỗng; /size, /bpp | :314–332 |
| /scale-desktop + /scale-device khi custom; hoặc /scale preset | :334–342 |
| /admin; /vmconnect[:guid]; /sec:nla,tls,rdp | :344–371 |
| /cert-name chỉ khi certName không rỗng; hiện biến luôn khởi tạo rỗng và không gán lại trong method | :274,373–376 |
| /network:auto; /rfx; /gfx hoặc /gfx:AVC444,AVC420,RFX,progressive (có H264) | :378–396 |
| +/-wallpaper, window-drag, menu-anims, themes, fonts, aero | :398–403; helper +/- :248–254 |
| /app:program + /app:workdir; hoặc /shell + /shell-dir | :405–417 |
| +/-async-channels, +/-async-update | :419–420 |
| /drive:sdcard,path; /load-balance-info | :422–432 |
| /clipboard và /disp luôn thêm; /printer nếu bật | :433–437 |
| /gateway:g:host:port[,u:...][,d:...][,p:...] khi bật gateway | :439–464 |
| /audio-mode:0 local /1 remote /2 disable; /sound khi 0 | :466–473 |
| /microphone; /dvc:rdpecam nếu camera và native hỗ trợ | :475–483 |
| /auto-reconnect từ preferences | :485–488 |
| /kbd:unicode:on, **/cert:ignore luôn thêm**, /log-level | :490–494 |

URI overload chỉ tự thêm argv[0], /gdi:sw, optional /client-hostname, /v, /u và query; không tự kế thừa các option Bookmark, gồm /cert:ignore, /disp, /clipboard (`J/services/LibFreeRDP.java:497–561`). Bước B có thể chọn URI nếu cần chính sách certificate riêng, không phải sửa JNI. Password trong URI là dữ liệu RAM nhạy cảm; không đưa URI vào UI/history/log: mẫu dùng openUri.getAuthority làm tiêu đề (:606–610), SessionState có Parcelable ghi URI/bookmark (:122–127), và BookmarkBase có đường persistence riêng (:287–369). Không dùng các đường persistence đó cho password.

## (c) Framebuffer và SurfaceView

| Class đầy đủ | Signature | Nguồn |
|---|---|---|
| com.freerdp.freerdpcore.services.LibFreeRDP | `public static boolean updateGraphics(long inst, Bitmap bitmap, int x, int y, int width, int height)` | `J/services/LibFreeRDP.java:564–568`; `C/android_freerdp.c:1028–1097` |
| com.freerdp.freerdpcore.services.LibFreeRDP | `public static boolean sendMonitorLayout(long inst, int width, int height)` | `J/services/LibFreeRDP.java:600–603`; `C/android_freerdp.c:1251–1264` |
| com.freerdp.freerdpcore.application.SessionState | `public BitmapDrawable getSurface()`; `public void setSurface(BitmapDrawable surface)` | `J/application/SessionState.java:107,112` |
| com.freerdp.freerdpcore.presentation.SessionView | `public void onSurfaceChange(SessionState session)` | `J/presentation/SessionView.java:161–174` |
| com.freerdp.freerdpcore.presentation.SessionView | `public void onDraw(@NonNull Canvas canvas)` | `J/presentation/SessionView.java:274–286` |

**Không có public API nhận Surface/SurfaceHolder/SurfaceView** trong LibFreeRDP (toàn bộ native declarations :136–179 và public methods :181–603). `SessionState.setSurface` nhận BitmapDrawable, tên "surface" không có nghĩa android.view.Surface. `updateGraphics` copy vùng (x,y,width,height) từ gdi->primary_buffer vào Bitmap, lock/unlock pixels; chấp nhận RGBA_8888 / RGB_565, kiểu khác false (`C/android_freerdp.c:1050–1097`). GDI được init PIXEL_FORMAT_RGBX32 (`C/android_freerdp.c:463`).

Luồng mẫu: native OnSettingsChanged -> tạo Bitmap đúng kích thước/bpp -> SessionState.setSurface; native OnGraphicsUpdate -> updateGraphics(bitmap,dirty rect) -> đánh dấu invalid và gửi Handler refresh UI; SessionView.onDraw scale Canvas rồi BitmapDrawable.draw (`J/presentation/SessionActivity.java:738–779`; `J/presentation/SessionView.java:146–174,274–286`). OnGraphicsResize thay Bitmap và gửi GRAPHICS_CHANGED (`J/presentation/SessionActivity.java:789–805`); native gdi_resize trước callback (`C/android_freerdp.c:207–221`).

**Đề xuất cho SurfaceView bước B:** tự trình bày Bitmap bằng Canvas/SurfaceHolder ở lớp app, quản lý surfaceCreated/Changed/Destroyed và tọa độ scale. Đây là thiết kế cần làm, không phải API FreeRDP đã có. Chỉ đổi kích thước vùng hiển thị thì có thể scale framebuffer; nếu muốn đổi desktop remote, gọi sendMonitorLayout sau khi DISP sẵn sàng, xử lý false và chờ OnGraphicsResize. Mẫu có gửi khi config thay đổi (`J/presentation/SessionActivity.java:389–411`); native trả false nếu chưa có channel/SendMonitorLayout (`C/android_disp.c:54–86`). Không bắt buộc gửi monitor layout mỗi lần Surface đổi size; không có native surfaceChanged hook trong declarations đã dẫn.

## (d) Connect, disconnect, thread và trạng thái

Tất cả signature trong bảng thuộc **com.freerdp.freerdpcore.services.LibFreeRDP**:

| Signature | Nguồn | Hành vi |
|---|---|---|
| `public static boolean connect(long inst)` | `J/services/LibFreeRDP.java:214–224`; `C/android_freerdp.c:970–989` | Kiểm tra state; native CreateThread. true chỉ là tạo thread được, chưa chứng minh login thành công. |
| `public static boolean disconnect(long inst)` | `J/services/LibFreeRDP.java:226–236` | Chỉ gọi native khi mInstanceState true; khi còn connecting có thể no-op trả true. |
| `public static boolean cancelConnection(long inst)` | `J/services/LibFreeRDP.java:238–241`; `C/android_freerdp.c:992–1025` | Gọi thẳng disconnect native: queue event, abort connect, đánh thức reconnect. Dùng cho đang connecting. |
| `public static void setForeground(long inst, boolean foreground)` | `J/services/LibFreeRDP.java:243–246`; `C/android_freerdp.c:905–915,625–630` | Giữ/cho phép reconnect bằng foregroundEvent. |
| `public static void setEventListener(EventListener l)` | `J/services/LibFreeRDP.java:181–184` | Một listener static toàn tiến trình; thay thế listener cũ. |

`public void connect(Context context)` của `com.freerdp.freerdpcore.application.SessionState` đặt config rồi connect (`J/application/SessionState.java:69–79`). Mẫu chạy wrapper này trong ConnectThread Java và native lại tạo worker riêng (`J/presentation/SessionActivity.java:613–644`; `C/android_freerdp.c:984`). Native thread gọi client_start -> freerdp_connect -> event loop -> disconnect -> client_stop -> OnDisconnected hoặc OnConnectionFailure theo status (`C/android_freerdp.c:699–738`). Callback JNI không được tự chuyển sang UI thread; helper attach thread hiện tại (`C/android_jni_callback.c:72–87,105–122`).

Không có public isConnected/getConnectionState trong LibFreeRDP; private mInstanceState được cập nhật ở OnConnectionSuccess, OnConnectionFailure, OnDisconnected (`J/services/LibFreeRDP.java:38,605–648`). `androidContext.is_connected` chỉ là field C, không có Java getter (`C/android_freerdp.h:33`; `J/services/LibFreeRDP.java:136–179`). App nên giữ state từ EventListener. Mẫu có `com.freerdp.freerdpcore.presentation.SessionViewModel.public LiveData<ConnectionState> getState()` (:62), `public void register(long instance)` (:67), `public void unregister()` (:90), enum IDLE/CONNECTING/CONNECTED/FAILED/DISCONNECTED (:35–42), mapping callback (:72–86). LiveData = androidx.lifecycle.LiveData (`J/presentation/SessionViewModel.java:16–20`). GlobalApp dispatch SessionEventListener qua mainHandler.post, khác với EventListener/UIEventListener được gọi trực tiếp từ thread JNI (`J/application/GlobalApp.java:54–74`; `J/services/LibFreeRDP.java:605–619,650–657`).

GlobalApp có `public static void registerSessionListener(long instance, SessionEventListener listener)` và `public static void unregisterSessionListener(long instance)` (`J/application/GlobalApp.java:58,63`), với nested interface đầy đủ `com.freerdp.freerdpcore.application.GlobalApp.SessionEventListener`: `void onConnectionSuccess()`, `void onConnectionFailure()`, `void onDisconnected()` (:47–53). Dùng đường này nếu giữ GlobalApp làm EventListener. `freerdp_get_last_error_string(long)` **private**, chưa có public wrapper (`J/services/LibFreeRDP.java:179,181–933`); thiếu chi tiết lỗi không chặn connect/render, không gọi private để bù.

Lifecycle cần cẩn thận: OnConnectionSuccess gọi listener trước khi ghi state true (:605–613); OnDisconnected/Failure cũng gọi listener trước khi xóa state (:616–647). Không freeInstance đồng bộ ngay trong các callback đó vì nó wait state mà chính callback chưa cập nhật; nên lịch teardown sau khi callback trả về. Source chứng minh thứ tự này, chưa kiểm chứng runtime race với native thread kết thúc (`J/services/LibFreeRDP.java:191–211,605–648`; `C/android_freerdp.c:729–738`).

## (e) Phím và chuột

| Class đầy đủ | Signature | Nguồn |
|---|---|---|
| com.freerdp.freerdpcore.services.LibFreeRDP | `public static boolean sendKeyEvent(long inst, int keycode, boolean down)` | `J/services/LibFreeRDP.java:575–578`; `C/android_freerdp.c:1100–1124` |
| com.freerdp.freerdpcore.services.LibFreeRDP | `public static boolean sendUnicodeKeyEvent(long inst, int keycode, boolean down)` | `J/services/LibFreeRDP.java:580–583`; `C/android_freerdp.c:1127–1146` |
| com.freerdp.freerdpcore.services.LibFreeRDP | `public static boolean isUnicodeInputSupported(long inst)` | `J/services/LibFreeRDP.java:585–588`; `C/android_freerdp.c:1149–1161` |
| com.freerdp.freerdpcore.services.LibFreeRDP | `public static boolean sendCursorEvent(long inst, int x, int y, int flags)` | `J/services/LibFreeRDP.java:570–573`; `C/android_freerdp.c:1164–1182` |
| com.freerdp.freerdpcore.utils.KeyboardMapper | `public void init(Context context)`; `public void setKeyProcessingListener(KeyProcessingListener listener)`; `public boolean processAndroidKeyEvent(KeyEvent event)` | `J/utils/KeyboardMapper.java:229,451,456` |
| com.freerdp.freerdpcore.utils.KeyboardMapper.KeyProcessingListener | `void processVirtualKey(int virtualKeyCode, boolean down)`; `void processUnicodeKey(int unicodeKey)`; `void switchKeyboard(int keyboardType)`; `void modifiersChanged()` | `J/utils/KeyboardMapper.java:796–805` |

`inst` là native handle. `sendKeyEvent.keycode` là **Windows virtual-key code** (có thể OR VK_EXT_KEY=0x100 theo mapper), không phải Android keycode, X11 keysym hay scan code đã tính sẵn. Native dùng GetVirtualScanCodeFromVirtualKeyCode(keycode,4), down=true -> KBD_FLAGS_DOWN, false -> RELEASE, lấy KBDEXT để thêm EXTENDED và gửi low byte scan code (`C/android_freerdp.c:1106–1112`; `J/utils/KeyboardMapper.java:204–205,283–292`). Boolean trả về phản ánh tạo/queue event, không xác nhận Windows đã xử lý (`C/android_freerdp.c:1114–1124,1172–1182`). Unicode path dùng unicode value vào android_event_unicodekey_new (`C/android_freerdp.c:1128–1134`); mẫu xử lý String từng char UTF-16 ở ACTION_MULTIPLE (`J/utils/KeyboardMapper.java:542–549`).

Mapping thật: keymapAndroid[KEYCODE_A]=VK_KEY_A=0x41, KEYCODE_0 -> 0x30, ENTER -> VK_RETURN=0x0D, DEL -> VK_BACK=0x08; arrow/home/end/page/insert/delete có extended flag; OEM punctuation, F1–F12 và numpad có bảng riêng (`J/utils/KeyboardMapper.java:35–39,72–82,236–340`). SessionActivity.onKeyDown/onKeyUp chuyển cho SessionInputManager rồi mapper (`J/presentation/SessionActivity.java:712–723`; `J/presentation/SessionInputManager.java:216–228`). Mapper ACTION_DOWN gửi modifiers cần thiết + VK down/up rồi release modifiers; phần lớn ACTION_UP bỏ qua, Win được buffer để phân biệt tap/combo (`J/utils/KeyboardMapper.java:456–539`). **Không sao chép giả định mapper gửi key-up vật lý một-một.** processVirtualKey gọi sendKeyEvent; Unicode có kiểm tra support, nếu không thì fallback (`J/presentation/SessionInputManager.java:464–481`).

Chuột: x/y là tọa độ desktop/framebuffer remote, flags là RDP PTRFLAGS; native không scale, chỉ queue nguyên giá trị (`C/android_freerdp.c:1164–1182`). Mẫu dùng bitmap và tọa độ chuột, gọi Mouse helper cho move/click/scroll (`J/presentation/SessionInputManager.java:270–284,329–447`). Constants: left=0x1000, right=0x2000, middle=0x4000, DOWN=0x8000, MOVE=0x0800; button-up bỏ bit DOWN; wheel=0x0200, negative=0x0100, horizontal=0x0400, delta=120 (`J/utils/Mouse.java:20–30,32–88`).

Public helper đầy đủ ở class **com.freerdp.freerdpcore.utils.Mouse**: `public static int getLeftButtonEvent(Context context, boolean down)` (:32), `getRightButtonEvent(Context context, boolean down)` (:40), `getMiddleButtonEvent(boolean down)` (:48), `getMoveEvent()` (:53), `getScrollEvent(Context context, boolean down)` (:58), `getScrollEvent(Context context, int amount)` (:64), `getHScrollEvent(Context context, boolean right)` (:71), `getHScrollEvent(Context context, int amount)` (:76); tất cả trả int và static public (`J/utils/Mouse.java`, từng dòng dẫn). amount là signed wheel units, helper áp invert/swap preferences (:32–88).

## (f) Toàn bộ callback Java/JNI và đăng ký

**Phân biệt hai tầng:** native gọi các `private static On…` có sẵn trong **com.freerdp.freerdpcore.services.LibFreeRDP**, không gọi method cùng tên trên RdpPlugin. Không cần tự viết JNI bridge. EventListener đăng ký bằng setEventListener; UIEventListener gắn vào SessionState có trong GlobalApp registry (`J/services/LibFreeRDP.java:181–184,605–865`; `J/application/SessionState.java:97–104`). `UIEventListener.OnVerifiyCertificateEx` cố ý ghi đúng spelling source có chữ **Verifiy**, còn native bridge tên **OnVerifyCertificateEx** (:684–695,898–899).

### Native -> LibFreeRDP: signature nguyên văn

Mọi method Java trong bảng có modifier `private static`, class đầy đủ **com.freerdp.freerdpcore.services.LibFreeRDP**. `long inst` đầu tiên luôn là session handle. Bảng giữ đúng Java declaration và JNI descriptor; JNI `J`=long, `I`=int, `Z`=boolean, `V`=void, `[J`=long[], `[I`=int[], `[B`=byte[].

| Java signature | JNI descriptor | Java source | Native source |
|---|---|---|---|
| `private static void OnConnectionSuccess(long inst)` | `(J)V` | `J/services/LibFreeRDP.java:605` | `C/android_freerdp.c:476` |
| `private static void OnConnectionFailure(long inst)` | `(J)V` | `J/services/LibFreeRDP.java:616` | `C/android_freerdp.c:735` |
| `private static void OnPreConnect(long inst)` | `(J)V` | `J/services/LibFreeRDP.java:627` | `C/android_freerdp.c:252` |
| `private static void OnDisconnecting(long inst)` | `(J)V` | `J/services/LibFreeRDP.java:633` | `C/android_freerdp.c:482` |
| `private static void OnDisconnected(long inst)` | `(J)V` | `J/services/LibFreeRDP.java:639` | `C/android_freerdp.c:733` |
| `private static void OnSettingsChanged(long inst, int width, int height, int bpp)` | `(JIII)V` | `J/services/LibFreeRDP.java:650` | `C/android_freerdp.c:472–475` |
| `private static boolean OnAuthenticate(long inst, StringBuilder username, StringBuilder domain, StringBuilder password)` | `(JLjava/lang/StringBuilder;Ljava/lang/StringBuilder;Ljava/lang/StringBuilder;)Z` | `J/services/LibFreeRDP.java:660` | `C/android_freerdp.c:497–520,529–537` |
| `private static boolean OnGatewayAuthenticate(long inst, StringBuilder username, StringBuilder domain, StringBuilder password)` | `(JLjava/lang/StringBuilder;Ljava/lang/StringBuilder;Ljava/lang/StringBuilder;)Z` | `J/services/LibFreeRDP.java:672` | `C/android_freerdp.c:497–520,538–542` |
| `private static int OnVerifyCertificateEx(long inst, String host, long port, String commonName, String subject, String issuer, String fingerprint, long flags)` | `(JLjava/lang/String;JLjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;J)I` | `J/services/LibFreeRDP.java:684` | `C/android_freerdp.c:567–571` |
| `private static int OnVerifyChangedCertificateEx(long inst, String host, long port, String commonName, String subject, String issuer, String fingerprint, String oldSubject, String oldIssuer, String oldFingerprint, long flags)` | `(JLjava/lang/String;JLjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;J)I` | `J/services/LibFreeRDP.java:698` | `C/android_freerdp.c:595–601` |
| `private static boolean OnExperimentalFeature(long inst, int feature)` | `(JI)Z` | `J/services/LibFreeRDP.java:715` | `C/android_freerdp.c:453–461` |
| `private static void OnGraphicsUpdate(long inst, int x, int y, int width, int height)` | `(JIIII)V` | `J/services/LibFreeRDP.java:726` | `C/android_freerdp.c:199–200` |
| `private static void OnGraphicsResize(long inst, int width, int height, int bpp)` | `(JIII)V` | `J/services/LibFreeRDP.java:736` | `C/android_freerdp.c:219–220` |
| `private static void OnRemoteClipboardChanged(long inst, String data)` | `(JLjava/lang/String;)V` | `J/services/LibFreeRDP.java:746` | `C/android_cliprdr.c:464` |
| `private static void OnRemoteClipboardImageChanged(long inst, byte[] data)` | `(J[B)V` | `J/services/LibFreeRDP.java:756` | `C/android_cliprdr.c:489` |
| `private static void OnPointerSet(long inst, int[] pixels, int width, int height, int hotX, int hotY)` | `(J[IIIII)V` | `J/services/LibFreeRDP.java:766` | `C/android_freerdp.c:312–327,1343–1344` |
| `private static void OnPointerSetNull(long inst)` | `(J)V` | `J/services/LibFreeRDP.java:777` | `C/android_freerdp.c:347` |
| `private static void OnReconnecting(long inst)` | `(J)V` | `J/services/LibFreeRDP.java:787` | `C/android_freerdp.c:630` |
| `private static void OnPointerSetDefault(long inst)` | `(J)V` | `J/services/LibFreeRDP.java:797` | `C/android_freerdp.c:355` |
| `private static void OnRailWindowUpdate(long inst, long windowId, int width, int height, int[] pixels)` | `(JJII[I)V` | `J/services/LibFreeRDP.java:807` | `C/android_freerdp.c:411–412,1345–1350` |
| `private static void OnRailWindowMove(long inst, long windowId, int x, int y, int w, int h)` | `(JJIIII)V` | `J/services/LibFreeRDP.java:818` | `C/android_rail.c:134,218,231,237` |
| `private static void OnRailWindowHide(long inst, long windowId)` | `(JJ)V` | `J/services/LibFreeRDP.java:828` | `C/android_rail.c:209` |
| `private static void OnRailWindowDestroy(long inst, long windowId)` | `(JJ)V` | `J/services/LibFreeRDP.java:838` | `C/android_rail.c:251` |
| `private static void OnRailSessionEnd(long inst)` | `(J)V` | `J/services/LibFreeRDP.java:848` | `C/android_rail.c:192` |
| `private static void OnRailMonitoredDesktop(long inst, long[] windowIds, long activeWindowId)` | `(J[JJ)V` | `J/services/LibFreeRDP.java:858` | `C/android_rail.c:84` |

### Public interfaces app implement

Các interface method bên dưới là implicitly `public abstract`; không có default implementation trong interface. Khi implement UIEventListener phải khai báo **tất cả** method để compile; "có thể trống" nghĩa là body no-op/return mặc định, không phải xóa method. Class đầy đủ ghi ở từng bảng.

**com.freerdp.freerdpcore.services.LibFreeRDP.EventListener**

| Signature (public abstract) | Nguồn |
|---|---|
| `void OnPreConnect(long instance)` | `J/services/LibFreeRDP.java:875` |
| `void OnConnectionSuccess(long instance)` | `J/services/LibFreeRDP.java:877` |
| `void OnConnectionFailure(long instance)` | `J/services/LibFreeRDP.java:879` |
| `void OnDisconnecting(long instance)` | `J/services/LibFreeRDP.java:881` |
| `void OnDisconnected(long instance)` | `J/services/LibFreeRDP.java:883` |

**com.freerdp.freerdpcore.services.LibFreeRDP.UIEventListener**

| Signature (public abstract) | Nguồn |
|---|---|
| `void OnSettingsChanged(int width, int height, int bpp)` | `J/services/LibFreeRDP.java:888` |
| `void OnReconnecting()` | `J/services/LibFreeRDP.java:890` |
| `boolean OnAuthenticate(StringBuilder username, StringBuilder domain, StringBuilder password)` | `J/services/LibFreeRDP.java:892` |
| `boolean OnGatewayAuthenticate(StringBuilder username, StringBuilder domain, StringBuilder password)` | `J/services/LibFreeRDP.java:895` |
| `int OnVerifiyCertificateEx(String host, long port, String commonName, String subject, String issuer, String fingerprint, long flags)` | `J/services/LibFreeRDP.java:898` |
| `int OnVerifyChangedCertificateEx(String host, long port, String commonName, String subject, String issuer, String fingerprint, String oldSubject, String oldIssuer, String oldFingerprint, long flags)` | `J/services/LibFreeRDP.java:901` |
| `boolean OnExperimentalFeature(int feature)` | `J/services/LibFreeRDP.java:905` |
| `void OnGraphicsUpdate(int x, int y, int width, int height)` | `J/services/LibFreeRDP.java:907` |
| `void OnGraphicsResize(int width, int height, int bpp)` | `J/services/LibFreeRDP.java:909` |
| `void OnRemoteClipboardChanged(String data)` | `J/services/LibFreeRDP.java:911` |
| `void OnRemoteClipboardImageChanged(byte[] data)` | `J/services/LibFreeRDP.java:913` |
| `void OnPointerSet(int[] pixels, int width, int height, int hotX, int hotY)` | `J/services/LibFreeRDP.java:915` |
| `void OnPointerSetNull()` | `J/services/LibFreeRDP.java:917` |
| `void OnPointerSetDefault()` | `J/services/LibFreeRDP.java:919` |
| `void OnRailWindowUpdate(long windowId, int width, int height, int[] pixels)` | `J/services/LibFreeRDP.java:921` |
| `void OnRailWindowMove(long windowId, int x, int y, int w, int h)` | `J/services/LibFreeRDP.java:923` |
| `void OnRailWindowHide(long windowId)` | `J/services/LibFreeRDP.java:925` |
| `void OnRailWindowDestroy(long windowId)` | `J/services/LibFreeRDP.java:927` |
| `void OnRailSessionEnd()` | `J/services/LibFreeRDP.java:929` |
| `void OnRailMonitoredDesktop(long[] windowIds, long activeWindowId)` | `J/services/LibFreeRDP.java:931` |

Đăng ký UI: `public void setUIEventListener(LibFreeRDP.UIEventListener uiEventListener)` của `com.freerdp.freerdpcore.application.SessionState` và `public LibFreeRDP.UIEventListener getUIEventListener()` (`J/application/SessionState.java:102,97`). Không có public setter UI listener trực tiếp theo handle trên LibFreeRDP; phải qua SessionState/GlobalApp như mục (a).

### Bắt buộc ở tầng nào; có thể mặc định ở đâu

| Nhóm | Yêu cầu / default có bằng chứng |
|---|---|
| Class/bridge JNI | Phải giữ LibFreeRDP và đúng tên/signature các bridge được gọi. JNI tìm class cố định, tạo object qua constructor ()V; callbacks dùng GetStaticMethodID. Nếu thiếu class thì JNI_OnLoad=-1; helper thiếu method chỉ log/goto finish, không clear exception, nên không được xem việc xóa bridge là an toàn (`C/android_freerdp_jni.h:23–25`; `C/android_freerdp.c:1333–1353`; `C/android_jni_callback.c:27–68,114–122,148–156,184–192`). Với nguyên library, các bridge này đã tồn tại, app không implement lại. |
| Lifecycle EventListener | Bridge OnPreConnect/Success/Failure/Disconnecting/Disconnected đã có; listener null được phép. Nên xử lý Success/Failure/Disconnected để state và teardown đúng. Các body EventListener có thể trống nhưng app sẽ không có thông báo trạng thái. State private vẫn cập nhật sau listener (`J/services/LibFreeRDP.java:605–648`). |
| Registry GlobalApp | Bắt buộc cho toàn bộ callback UI dispatch hiện có: getSession gọi trực tiếp map.get, không guard map null (`J/application/GlobalApp.java:117–119`; `J/services/LibFreeRDP.java:650–865`). Không thể thay bằng chỉ setEventListener. |
| OnSettingsChanged / OnGraphicsUpdate / OnGraphicsResize | Không bắt buộc để TCP/NLA thành công, nhưng bắt buộc có xử lý thật để mục tiêu render hoạt động: tạo/copy/thay bitmap như mẫu. Null listener thì bridge return/bỏ qua (`J/services/LibFreeRDP.java:650–658,726–744`; `J/presentation/SessionActivity.java:738–805`). |
| OnAuthenticate | Khi native cần credentials callback, phải điền StringBuilder và return true; false hủy xác thực. Không có session/listener -> false. Native tạo builders từ username/domain/password hiện tại, đọc lại nếu true; thứ tự Java là username, domain, password, không phải thứ tự tham số C char** (`C/android_freerdp.c:497–520,529–545`; `J/services/LibFreeRDP.java:660–670`). Có thể đã cung cấp credentials bằng config, nhưng không giả định callback luôn được bỏ qua. Mẫu mở dialog trên UI, worker chờ, sửa builders rồi trả kết quả (`J/presentation/SessionDialogs.java:141–176`; `J/presentation/SessionActivity.java:809–812`). |
| OnGatewayAuthenticate | Tương tự nhưng chỉ gateway reasons GW_AUTH_HTTP/RDG/RPC; không dùng gateway thì có thể return false (`C/android_freerdp.c:538–542`; `J/services/LibFreeRDP.java:672–681`). |
| Verify certificate / changed certificate | Chỉ cần xử lý chấp thuận khi policy native yêu cầu verify; thiếu session/listener trả 0, không được coi là chấp thuận (`J/services/LibFreeRDP.java:684–712`). Bookmark path luôn /cert:ignore (:491), URI cho phép chính sách khác (:529–556). Giá trị chuẩn: 0=từ chối, 1=chấp thuận và lưu certificate, 2=chấp thuận chỉ phiên này (`U/include/freerdp/freerdp.h:244–249,291–299`; `U/libfreerdp/crypto/tls.c:2080–2100`). Không suy diễn từ tên setting mẫu. |
| OnExperimentalFeature | Return false làm post_connect thất bại nếu RemoteApp hoặc camera được bật. Bridge không có session/listener trả true. Cho desktop thường không dùng tính năng đó; có thể return true hoặc false theo chính sách sản phẩm (`C/android_freerdp.c:453–461`; `J/services/LibFreeRDP.java:715–724`). |
| Pointer Set/Null/Default | Tính năng hiển thị con trỏ; UI body có thể no-op nếu chưa vẽ cursor. OnPointerSet signature có int[] và hotspot; native cache method trong JNI_OnLoad, không có nhánh ExceptionClear riêng cho việc thiếu nó, vì vậy giữ bridge nguyên vẹn (`C/android_freerdp.c:303–355,1343–1351`; `J/services/LibFreeRDP.java:766–785,797–805`). |
| OnReconnecting | Thông báo phụ, có thể no-op; native đã làm retry; callback được gửi sau khi chờ foreground (`C/android_freerdp.c:609–631`; `J/services/LibFreeRDP.java:787–795`). |
| Clipboard text/image | UI có thể no-op; xử lý khi cần clipboard. byte[] callback chỉ ảnh, không nhầm int[] framebuffer/cursor (`C/android_cliprdr.c:464,489`; `J/services/LibFreeRDP.java:746–764`). |
| RAIL callbacks | RemoteApp: OnRailWindowUpdate(int[]), Move, Hide, Destroy, SessionEnd, MonitoredDesktop(long[]). Desktop thường có thể no-op. Riêng native OnRailWindowUpdate lookup thiếu được clear exception và disable RAIL display (`C/android_freerdp.c:1345–1350`); các bridge RAIL còn lại vẫn nên giữ vì helper không clear exception (`C/android_rail.c:84,134,192,209,251`; `C/android_jni_callback.c:114–126`; `J/services/LibFreeRDP.java:807–865`). |

`[J` ở OnRailMonitoredDesktop = long[] windowIds và long activeWindowId, không phải handle array cho session. `[I` ở OnPointerSet = cursor pixels với width/height/hotX/hotY; `[I` ở OnRailWindowUpdate = pixels của windowId với width/height (`J/services/LibFreeRDP.java:766–774,807–815,858–865`; native descriptor trong bảng trên).

### Entry point Context/Bitmap; âm thanh và tính năng phụ

Context cần cho newInstance và hai overload setConnectionInfo; native new gọi `android.content.Context.getFilesDir(): java.io.File`, rồi `java.io.File.getAbsolutePath(): String` (`C/android_freerdp.c:814–850`). Đây là Android framework method, không phải custom callback cần app implement. Bitmap chỉ đi từ Java vào updateGraphics (`J/services/LibFreeRDP.java:160–161,564–568`; `C/android_freerdp.c:1028–1097`). Không callback On… nào ở bảng trên nhận Context, Bitmap, Surface hoặc SurfaceHolder.

Java helper còn dùng StringBuilder constructor/toString để trao đổi credentials (`C/android_jni_utils.c:35–100`), không yêu cầu callback riêng. Trong callback sites của freeRDPCore/src/main/cpp (android_freerdp.c, android_cliprdr.c, android_rail.c nêu ở bảng), không có callback Java OnAudio: wrapper chỉ bật /audio-mode,/sound,/microphone, camera channel ở config (`J/services/LibFreeRDP.java:466–483`). CHƯA CHẮC về callback/backend âm thanh nằm ngoài thư mục client JNI đã khảo sát; không tuyên bố bảng này bao trùm mọi JNI của WinPR/channel library khác.

API clipboard public cùng class **com.freerdp.freerdpcore.services.LibFreeRDP**: `public static boolean sendClipboardData(long inst, String data)` (`J/services/LibFreeRDP.java:590–593`), `public static boolean sendClipboardImageData(long inst, byte[] data, String mimeType)` (:595–598). Không cần gọi cho mục tiêu bàn phím + desktop của bước B.

## Phụ lục — Public model API cho toàn bộ tùy chọn nhánh Bookmark

Các signature sau được trích trực tiếp từ source, giữ annotation và tên tham số; chỉ liệt kê constructors không đối số, getter/setter cấu hình (bỏ Parcelable/persistence). Chúng bổ sung mục (b), không phải đề nghị bật mọi tính năng. Modifier `public` không ghi static nghĩa là instance method. Nguồn mỗi hàng là `J/domain/BookmarkBase.java`.

### com.freerdp.freerdpcore.domain.BookmarkBase

| Signature | Source |
|---|---|
| `public BookmarkBase()` | `J/domain/BookmarkBase.java:143` |
| `public int getType()` | `J/domain/BookmarkBase.java:147` |
| `public void setType(int type)` | `J/domain/BookmarkBase.java:152` |
| `public long getId()` | `J/domain/BookmarkBase.java:157` |
| `public void setId(long id)` | `J/domain/BookmarkBase.java:162` |
| `@NonNull public String getLabel()` | `J/domain/BookmarkBase.java:167` |
| `public void setLabel(@NonNull String label)` | `J/domain/BookmarkBase.java:172` |
| `@NonNull public String getUsername()` | `J/domain/BookmarkBase.java:177` |
| `public void setUsername(@NonNull String username)` | `J/domain/BookmarkBase.java:182` |
| `@NonNull public String getPassword()` | `J/domain/BookmarkBase.java:187` |
| `public void setPassword(@NonNull String password)` | `J/domain/BookmarkBase.java:192` |
| `@NonNull public String getDomain()` | `J/domain/BookmarkBase.java:197` |
| `public void setDomain(@NonNull String domain)` | `J/domain/BookmarkBase.java:202` |
| `@NonNull public ScreenSettings getScreenSettings()` | `J/domain/BookmarkBase.java:207` |
| `@NonNull public PerformanceFlags getPerformanceFlags()` | `J/domain/BookmarkBase.java:212` |
| `@NonNull public AdvancedSettings getAdvancedSettings()` | `J/domain/BookmarkBase.java:217` |
| `@NonNull public DebugSettings getDebugSettings()` | `J/domain/BookmarkBase.java:222` |
| `@NonNull public String getHostname()` | `J/domain/BookmarkBase.java:227` |
| `public void setHostname(@NonNull String hostname)` | `J/domain/BookmarkBase.java:232` |
| `public int getPort()` | `J/domain/BookmarkBase.java:237` |
| `public void setPort(int port)` | `J/domain/BookmarkBase.java:242` |
| `public boolean getEnableGatewaySettings()` | `J/domain/BookmarkBase.java:247` |
| `public void setEnableGatewaySettings(boolean enableGatewaySettings)` | `J/domain/BookmarkBase.java:252` |
| `@NonNull public GatewaySettings getGatewaySettings()` | `J/domain/BookmarkBase.java:257` |
| `public boolean isDirectConnect()` | `J/domain/BookmarkBase.java:262` |
| `public void setDirectConnect(boolean directConnect)` | `J/domain/BookmarkBase.java:267` |
| `@NonNull public ScreenSettings getActiveScreenSettings()` | `J/domain/BookmarkBase.java:272` |
| `@NonNull public PerformanceFlags getActivePerformanceFlags()` | `J/domain/BookmarkBase.java:277` |

### com.freerdp.freerdpcore.domain.BookmarkBase.PerformanceFlags

| Signature | Source |
|---|---|
| `public PerformanceFlags()` | `J/domain/BookmarkBase.java:457` |
| `public boolean getRemoteFX()` | `J/domain/BookmarkBase.java:474` |
| `public void setRemoteFX(boolean remotefx)` | `J/domain/BookmarkBase.java:479` |
| `public boolean getGfx()` | `J/domain/BookmarkBase.java:484` |
| `public void setGfx(boolean gfx)` | `J/domain/BookmarkBase.java:489` |
| `public boolean getH264()` | `J/domain/BookmarkBase.java:494` |
| `public void setH264(boolean h264)` | `J/domain/BookmarkBase.java:499` |
| `public boolean getWallpaper()` | `J/domain/BookmarkBase.java:504` |
| `public void setWallpaper(boolean wallpaper)` | `J/domain/BookmarkBase.java:509` |
| `public boolean getTheming()` | `J/domain/BookmarkBase.java:514` |
| `public void setTheming(boolean theming)` | `J/domain/BookmarkBase.java:519` |
| `public boolean getFullWindowDrag()` | `J/domain/BookmarkBase.java:524` |
| `public void setFullWindowDrag(boolean fullWindowDrag)` | `J/domain/BookmarkBase.java:529` |
| `public boolean getMenuAnimations()` | `J/domain/BookmarkBase.java:534` |
| `public void setMenuAnimations(boolean menuAnimations)` | `J/domain/BookmarkBase.java:539` |
| `public boolean getFontSmoothing()` | `J/domain/BookmarkBase.java:544` |
| `public void setFontSmoothing(boolean fontSmoothing)` | `J/domain/BookmarkBase.java:549` |
| `public boolean getDesktopComposition()` | `J/domain/BookmarkBase.java:554` |
| `public void setDesktopComposition(boolean desktopComposition)` | `J/domain/BookmarkBase.java:559` |

### com.freerdp.freerdpcore.domain.BookmarkBase.ScreenSettings

| Signature | Source |
|---|---|
| `public ScreenSettings()` | `J/domain/BookmarkBase.java:610` |
| `public void setResolution(@NonNull String resolution, int width, int height)` | `J/domain/BookmarkBase.java:663` |
| `public int getResolution()` | `J/domain/BookmarkBase.java:690` |
| `public void setResolution(int resolution)` | `J/domain/BookmarkBase.java:695` |
| `@NonNull public String getResolutionString()` | `J/domain/BookmarkBase.java:706` |
| `public boolean isPredefined()` | `J/domain/BookmarkBase.java:714` |
| `public boolean isAutomatic()` | `J/domain/BookmarkBase.java:720` |
| `public boolean isFitScreen()` | `J/domain/BookmarkBase.java:726` |
| `public boolean isCustom()` | `J/domain/BookmarkBase.java:732` |
| `public int getWidth()` | `J/domain/BookmarkBase.java:738` |
| `public void setWidth(int width)` | `J/domain/BookmarkBase.java:744` |
| `public int getHeight()` | `J/domain/BookmarkBase.java:749` |
| `public void setHeight(int height)` | `J/domain/BookmarkBase.java:755` |
| `public int getColors()` | `J/domain/BookmarkBase.java:760` |
| `public void setColors(int colors)` | `J/domain/BookmarkBase.java:766` |
| `public void setScale(@NonNull String mode, int desktop, int device)` | `J/domain/BookmarkBase.java:771` |
| `public boolean isCustomScale()` | `J/domain/BookmarkBase.java:778` |
| `@NonNull public String getScaleMode()` | `J/domain/BookmarkBase.java:783` |
| `public int getScalePreset()` | `J/domain/BookmarkBase.java:788` |
| `public int getScaleDesktop()` | `J/domain/BookmarkBase.java:797` |
| `public int getScaleDevice()` | `J/domain/BookmarkBase.java:802` |

### com.freerdp.freerdpcore.domain.BookmarkBase.DebugSettings

| Signature | Source |
|---|---|
| `public DebugSettings()` | `J/domain/BookmarkBase.java:844` |
| `@NonNull public String getDebugLevel()` | `J/domain/BookmarkBase.java:872` |
| `public void setDebugLevel(@NonNull String debug)` | `J/domain/BookmarkBase.java:878` |
| `public boolean getAsyncUpdate()` | `J/domain/BookmarkBase.java:883` |
| `public void setAsyncUpdate(boolean enabled)` | `J/domain/BookmarkBase.java:888` |
| `public boolean getAsyncChannel()` | `J/domain/BookmarkBase.java:893` |
| `public void setAsyncChannel(boolean enabled)` | `J/domain/BookmarkBase.java:898` |

### com.freerdp.freerdpcore.domain.BookmarkBase.AdvancedSettings

| Signature | Source |
|---|---|
| `public AdvancedSettings()` | `J/domain/BookmarkBase.java:952` |
| `public int getTlsSecLevel()` | `J/domain/BookmarkBase.java:1001` |
| `public void setTlsSecLevel(int level)` | `J/domain/BookmarkBase.java:1006` |
| `public void setTlsMinLevel(int level)` | `J/domain/BookmarkBase.java:1011` |
| `public int getTlsMinLevel()` | `J/domain/BookmarkBase.java:1016` |
| `@NonNull public String getLoadBalanceInfo()` | `J/domain/BookmarkBase.java:1021` |
| `public void setLoadBalanceInfo(@NonNull String info)` | `J/domain/BookmarkBase.java:1026` |
| `public boolean getRedirectSDCard()` | `J/domain/BookmarkBase.java:1030` |
| `public void setRedirectSDCard(boolean redirectSDCard)` | `J/domain/BookmarkBase.java:1035` |
| `public boolean getRedirectPrinter()` | `J/domain/BookmarkBase.java:1040` |
| `public void setRedirectPrinter(boolean redirectPrinter)` | `J/domain/BookmarkBase.java:1045` |
| `public int getRedirectSound()` | `J/domain/BookmarkBase.java:1050` |
| `public void setRedirectSound(int redirect)` | `J/domain/BookmarkBase.java:1056` |
| `public boolean getRedirectMicrophone()` | `J/domain/BookmarkBase.java:1061` |
| `public void setRedirectMicrophone(boolean redirect)` | `J/domain/BookmarkBase.java:1066` |
| `public boolean getRedirectCamera()` | `J/domain/BookmarkBase.java:1071` |
| `public void setRedirectCamera(boolean redirect)` | `J/domain/BookmarkBase.java:1076` |
| `public int getSecurity()` | `J/domain/BookmarkBase.java:1081` |
| `public void setSecurity(int security)` | `J/domain/BookmarkBase.java:1087` |
| `public boolean getConsoleMode()` | `J/domain/BookmarkBase.java:1092` |
| `public void setConsoleMode(boolean consoleMode)` | `J/domain/BookmarkBase.java:1097` |
| `@NonNull public String getRemoteProgram()` | `J/domain/BookmarkBase.java:1102` |
| `public void setRemoteProgram(@NonNull String remoteProgram)` | `J/domain/BookmarkBase.java:1107` |
| `@NonNull public String getAlternateShell()` | `J/domain/BookmarkBase.java:1112` |
| `public void setAlternateShell(@NonNull String alternateShell)` | `J/domain/BookmarkBase.java:1117` |
| `@NonNull public String getWorkDir()` | `J/domain/BookmarkBase.java:1122` |
| `public void setWorkDir(@NonNull String workDir)` | `J/domain/BookmarkBase.java:1127` |
| `public boolean getVmConnectMode()` | `J/domain/BookmarkBase.java:1132` |
| `public void setVmConnectMode(boolean vmConnectMode)` | `J/domain/BookmarkBase.java:1137` |
| `@NonNull public String getVmConnectGuid()` | `J/domain/BookmarkBase.java:1142` |
| `public void setVmConnectGuid(@NonNull String vmConnectGuid)` | `J/domain/BookmarkBase.java:1147` |

### com.freerdp.freerdpcore.domain.BookmarkBase.GatewaySettings

| Signature | Source |
|---|---|
| `public GatewaySettings()` | `J/domain/BookmarkBase.java:1201` |
| `@NonNull public String getHostname()` | `J/domain/BookmarkBase.java:1214` |
| `public void setHostname(@NonNull String hostname)` | `J/domain/BookmarkBase.java:1219` |
| `public int getPort()` | `J/domain/BookmarkBase.java:1224` |
| `public void setPort(int port)` | `J/domain/BookmarkBase.java:1229` |
| `@NonNull public String getUsername()` | `J/domain/BookmarkBase.java:1234` |
| `public void setUsername(@NonNull String username)` | `J/domain/BookmarkBase.java:1239` |
| `@NonNull public String getPassword()` | `J/domain/BookmarkBase.java:1244` |
| `public void setPassword(@NonNull String password)` | `J/domain/BookmarkBase.java:1249` |
| `@NonNull public String getDomain()` | `J/domain/BookmarkBase.java:1254` |
| `public void setDomain(@NonNull String domain)` | `J/domain/BookmarkBase.java:1259` |

## BLOCKER

**Không tìm thấy BLOCKER do thiếu API public cho connect/NLA, credentials, resolution, render bitmap hay input.** Hai overload public setConnectionInfo đi tới parser; createSession/setUIEventListener cho phép dùng ngoài SessionActivity; updateGraphics/sendKeyEvent/sendCursorEvent đều public (`J/services/LibFreeRDP.java:186–189,257–262,497–562,564–603`; `J/application/GlobalApp.java:103–119`; `J/application/SessionState.java:102–104`).

Không có public attachSurface hoặc public parseArguments/getLastErrorString, nhưng attachSurface được thay bằng trình bày bitmap của app, config có public wrapper đủ dùng; chi tiết lỗi không phải điều kiện để nối được. Không gọi private, reflection hoặc tạo JNI mới. **Điều kiện tích hợp bắt buộc bước B** là khởi tạo GlobalApp qua Application lifecycle; nếu bước B bị giới hạn chỉ sửa RdpPlugin và không được chỉnh Application/manifest thì đường callback hiện tại sẽ bị chặn bởi registry private không được initialize (`J/application/GlobalApp.java:43,117–119,137–147`; `A/android/app/src/main/AndroidManifest.xml:8`). Đây là ràng buộc scope cần biết, không kết luận upstream thiếu API để chạy ngoài Activity.

## Chưa chắc chắn

- **CHƯA CHẮC** artifact AAR CI có cùng bytecode/native symbols với source tag đang đọc; không có AAR để kiểm chứng. Hành vi document dựa source, không chứng minh APK runtime; loader cần freerdp-android và dependent freerdp-client/freerdp/winpr major libraries (`J/services/LibFreeRDP.java:81–123`).
- **CHƯA CHẮC** kết nối tới PC 100.101.127.41:3389, account format/domain và policy NLA/certificate phía server; không test mạng. Source chỉ chứng minh đường truyền /v,/port,/u,/d,/p,/sec:nla (`J/services/LibFreeRDP.java:280–328,358–362`). IP/port này là mục tiêu do yêu cầu cung cấp, không phải giá trị hardcode có trong source.
- **CHƯA CHẮC** việc tích hợp GlobalApp subclass có tương tác với Flutter Application hiện tại hay thư viện in/receiver/preferences trên APK Ace; phải xác minh ở bước B. Source mẫu chỉ chứng minh lifecycle và manifest mẫu (`J/application/GlobalApp.java:137–158`; `S/AndroidManifest.xml:6–7`; `A/android/app/src/main/AndroidManifest.xml:8`).
- **CHƯA CHẮC** rendering SurfaceView/Canvas, đồng bộ bitmap giữa callback native và UI, dispose an toàn khi surface bị hủy, freeze/reconnect dưới lifecycle Flutter; mẫu vẽ custom View/BitmapDrawable, chưa có bản SurfaceView chạy thật (`J/presentation/SessionView.java:274–286`; `J/presentation/SessionActivity.java:768–805`).
- **CHƯA CHẮC** timing teardown tuyệt đối an toàn giữa callback kết thúc và native thread thực sự ExitThread, đặc biệt cancel trước OnConnectionSuccess; wrapper state chỉ đánh dấu khi success, freeInstance không join thread trong Java (`J/services/LibFreeRDP.java:191–241,605–648`; `C/android_freerdp.c:729–738`). Cần kiểm tra kỹ trước triển khai bước B.
- **CHƯA CHẮC** key repeat, giữ phím liên tục, mọi layout laptop/IME và Unicode ngoài BMP; mapper mẫu thường ghép down/up ngay tại ACTION_DOWN, ACTION_MULTIPLE duyệt char (`J/utils/KeyboardMapper.java:456–549`). Mapping signature đã chắc; trải nghiệm keyboard cần kiểm tra runtime.
- **CHƯA CHẮC** server hỗ trợ DISP/hot resize và H264 build CI; sendMonitorLayout có thể false khi channel chưa có, H264 dựa probe runtime (`C/android_disp.c:54–86`; `J/services/LibFreeRDP.java:105–117,126–129`).
- **CHƯA CHẮC** trust policy/certificate thực tế trên server và callback âm thanh ngoài client JNI scope. Giá trị certificate 0/1/2 đã được xác minh (từ chối/lưu/chỉ phiên này), nhưng chưa chạy kiểm chứng certificate store trên APK (`U/include/freerdp/freerdp.h:244–249,291–299`; `U/libfreerdp/crypto/tls.c:2080–2100`).

## Kết luận cho bước B

**ĐỦ API public theo source 3.33.0** để mở phiên RDP thật và lấy framebuffer, nhập credentials không bắt buộc lưu chúng; không cần gọi native private. Đây là kết luận về khả năng API, chưa phải xác nhận kết nối thành công trên máy Windows (`J/services/LibFreeRDP.java:186–189,257–495,497–603`; `J/application/GlobalApp.java:103–119`; `J/application/SessionState.java:102–104`).

Thứ tự đề xuất, chưa triển khai trong bước A:

1. Tích hợp Android Application extends core GlobalApp, để framework gọi onCreate khởi tạo registry; chuẩn bị listener trạng thái và renderer bitmap (`J/application/GlobalApp.java:137–158`; `S/java/com/freerdp/afreerdp/application/GlobalApp.java:3`; `J/services/LibFreeRDP.java:873–931`).
2. Nhận thông tin Windows từ UI trong RAM; tạo BookmarkBase TYPE_MANUAL hoặc Uri xây bằng Android URI builder, không ghi password/URI vào storage/log. Đặt host/port, username/domain/password, size, /sec:nla; chọn policy certificate rõ ràng, nhớ Bookmark overload tự thêm /cert:ignore (`J/domain/BookmarkBase.java:143–152,182–242,663–688,1087`; `J/services/LibFreeRDP.java:280–328,330–331,358–362,491,529–556`).
3. GlobalApp.createSession(config,context), lấy handle, kiểm tra !=0; gắn SessionState.setUIEventListener trước connect. Đăng ký lifecycle qua GlobalApp.registerSessionListener để giữ listener GlobalApp đang có, hoặc thay EventListener có chủ đích (`J/application/GlobalApp.java:58–65,103–119,147`; `J/application/SessionState.java:82–85,102–104`; `J/services/LibFreeRDP.java:181–189`).
4. Gọi LibFreeRDP.setConnectionInfo và kiểm tra boolean; nếu true gọi LibFreeRDP.connect. Có worker native nên không dùng boolean connect làm trạng thái login. Xử lý auth StringBuilder khi được hỏi; update UI qua main thread (`J/services/LibFreeRDP.java:214–224,494,561,660–670`; `C/android_freerdp.c:497–520,970–989`; `J/presentation/SessionActivity.java:768–779,809–812`).
5. OnSettingsChanged tạo bitmap; OnGraphicsUpdate gọi updateGraphics rồi trình bày lên SurfaceView nửa trên; OnGraphicsResize thay bitmap; map tọa độ view sang desktop, gửi sendKeyEvent (Windows VK)/sendUnicodeKeyEvent và sendCursorEvent (`J/presentation/SessionActivity.java:738–805`; `J/services/LibFreeRDP.java:564–603`; `C/android_freerdp.c:1109–1112`). Renderer SurfaceView là phần app cần viết ở bước B, không có API native attachSurface.
6. Nếu cần đổi desktop remote thì sendMonitorLayout sau DISP sẵn sàng; surface resize đơn thuần có thể scale. Dừng đang kết nối bằng cancelConnection, ngắt phiên thành công bằng disconnect; lịch detach/freeSession sau callback kết thúc và rà soát race thread trước khi chọn lifecycle cụ thể (`C/android_disp.c:54–86`; `J/services/LibFreeRDP.java:191–241,605–648`; `J/application/GlobalApp.java:128–134`). Không tự thêm JNI để giải quyết phần chưa chắc chắn.

Dừng ở tài liệu này; không chỉnh code app, không build, không cài đặt, không truy cập mạng.
