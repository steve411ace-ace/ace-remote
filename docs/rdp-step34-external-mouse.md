# Bước 34 — Chuột rời điều khiển PC trong phiên RDP

Ngày: 2026-11-14. Version 1.5.3+20, CI run #20. Commit VM/PC xem
`git log` nhánh `rdp-prototype` ("step 34").

## Yêu cầu của An

1. Chuột rời (chuột PC) cắm vào điện thoại phải điều khiển được chuột
   máy tính trong phiên RDP — nhưng **chỉ trên phần màn hình PC** (nửa
   trên), không áp dụng trên bàn phím.
2. Khi có chuột cắm vào thì **ẩn 2 phím Left/Right** kẹp phím Space để
   **phím Space dài ra** (chuột đã có nút thật rồi); rút chuột ra thì
   2 phím hiện lại.

## Triệu chứng cũ (đã xác minh từ code)

- Native `RdpPlugin.onTouch` nhận MỌI motion event tới SurfaceView, kể
  cả click chuột (ACTION_DOWN với source SOURCE_MOUSE). Logic chạm coi
  click như chạm: bấm nhanh = click trái, giữ 500ms = click phải, kéo =
  kéo-thả trái. Nên chuột rời "vào như chạm": click thì được, nhưng
  di chuột không bấm thì con trỏ PC đứng yên, không có click phải thật,
  không có lăn chuột.
- Không có `OnHoverListener` / `OnGenericMotionListener` nào trên
  surface (hover và wheel không bao giờ tới FreeRDP).
- Dart không có xử lý chuột nào (không `MouseRegion`, không kiểm tra
  `PointerDeviceKind`).

## Thiết kế

Chuột do tầng Dart sở hữu (di tuyệt đối, bấm nhả, lăn qua channel);
đường chạm native bỏ qua event chuột để một click không bắn 2 lần.

### Dart (`lib/main.dart`, `_RemotePageState`)

- `mouseControl(child)` bọc vùng màn hình remote (`RdpConnectionPane`)
  trong `MouseRegion` + `Listener`:
  - `onHover` → `sendMouseMove` (tuyệt đối, tọa độ surface px =
    logical px × dpr). Chỉ khi đã `connected`.
  - `onPointerDown/Move` (chỉ `PointerDeviceKind.mouse`) → theo dõi
    bitmask nút đang giữ, gửi `sendMouseButton(down)` cho nút mới bấm;
    kéo khi giữ nút cũng gửi move tuyệt đối (kéo-thả trái/phải thật).
  - `onPointerUp` → gửi `sendMouseButton(up)` cho nút vừa nhả (so
    bitmask cũ/mới).
  - `onPointerCancel` / `dispose` → `_mouseReleaseAll()` nhả hết nút
    đang giữ (tránh kẹt nút trái trong phiên).
  - `onPointerSignal` (`PointerScrollEvent`) → `scrollWheel(dy > 0)`,
    một notch mỗi event, chỉ cuộn dọc.
- Chuột chỉ tác động trong vùng remote: `Listener` bọc mỗi
  `RdpConnectionPane`, bàn phím giữ nguyên (bấm phím bằng chuột vẫn gõ
  như chạm; vuốt trên phím vẫn di chuột tương đối như cũ).
- Bàn phím (`keyboardPanel`, hàng 5): bọc trong `ValueListenableBuilder`
  theo `MouseConnection.connected`; khi `rdpMode && mouseConnected` thì
  ẩn 2 phím Left/Right và Space dài thêm `2 × modU` (tổng hàng không
  đổi nên các phím khác giữ nguyên cỡ). Agent mode luôn hiện 2 phím
  (chuột không lái con trỏ agent).

### Dart (`lib/rdp_surface.dart`)

- `RdpController.sendMouseMove(Offset)` → channel `'mouseMove'`
  `{x, y}` (surface px); `sendMouseButton(Offset, button, down)` →
  `'mouseButton'` `{x, y, button: 'left'/'right'/'middle', down}`.
  Cả hai `try/catch` `PlatformException` (view detach giữa chừng không
  được làm lỗi UI — hover gọi rất dày).
- `MouseConnection` (static): `ValueNotifier<bool> connected` + channel
  `'vn.aceremote.app/input'`. `start()` hỏi trạng thái hiện tại
  (`'isMouseConnected'`) rồi nghe `'mouseChanged'` khi cắm/rút.
  **Bẫy:** `MissingPluginException` KHÔNG phải `PlatformException`
  (xem `message_codec.dart:205` — `implements Exception`), nên phải
  `catch (_)` — bản đầu chỉ bắt `PlatformException` đã làm rớt test
  `remote_test.dart` "Live polling recovers..." (nó chạy trong
  `runAsync`, lỗi async không được nuốt). Không có channel (test, web)
  thì giữ `false`.

### Native (`RdpPlugin.kt`)

- `onTouch`: đầu hàm, `if (event.isFromSource(InputDevice.SOURCE_MOUSE))
  return false` — chuột không đi đường chạm nữa.
- `surfaceToFramebuffer(xPx, yPx): Pair<Int, Int>?` — cùng công thức
  aspect-fit với `onTouch` (tâm letterbox trừ ra); null = ngoài màn
  hình PC hoặc chưa có frame.
- Channel `'mouseMove'` `{x, y}` → đổi tọa độ, đặt `lastX/lastY`,
  `touched = true`, gửi `PTRFLAGS_MOVE` (đường MOVE đã có coalescing
  `lastMovePending` nên hover dày không spam FreeRDP).
- Channel `'mouseButton'` `{x, y, button, down}` → bấm = MOVE rồi
  `flag | PTRFLAGS_DOWN` (như `clickAt`), nhả = bare flag.
- `RdpPlugin.onAttachedToEngine`: channel `'vn.aceremote.app/input'` +
  `InputManager.InputDeviceListener` (đăng ký với main Handler);
  `'isMouseConnected'` quét `inputDeviceIds` tìm thiết bị
  `supportsSource(SOURCE_MOUSE)`; đổi trạng thái thì push
  `'mouseChanged'` `{connected}`. Hủy đăng ký ở `onDetachedFromEngine`.

## Kiểm chứng

- `flutter analyze`: 0 issue.
- `flutter test`: 102/102 pass (98 cũ + 4 mới).
- Test mới (`test/rdp_surface_test.dart`):
  - Cắm chuột → hàng 5 mất Left/Right, Space dài từ 4.5× lên 7.0×
    phím chữ (tỉ lệ, không đo px tuyệt đối — flex rounding làm lệch
    ~3px); rút chuột → 2 phím hiện lại.
  - Agent mode vẫn hiện Left/Right dù có chuột.
  - `RdpController.sendMouseMove/sendMouseButton` gọi đúng channel
    method + args.
  - Hover/click/lăn chuột (dispatch `PointerHoverEvent` /
    `PointerDownEvent` / `PointerUpEvent` / `PointerScrollEvent` qua
    test binding) → đúng `'mouseMove'` / `'mouseButton'` down/up /
    `'scroll'`; dpr trong test mặc định là 3.0 nên test phải pin
    `tester.view.devicePixelRatio = 1.0` (reset sau test).
- CI run #20 (xem chat): build AAR + APK + Firebase như mọi lần.
- **Chưa kiểm chứng trên máy thật**: cần An test với chuột rời thật
  trên Fold6 — di chuột trên màn hình PC, click trái/phải, lăn chuột,
  cắm/rút chuột xem 2 phím Left/Right ẩn/hiện.

## Ghi chú

- Hover chuột trên Android: con trỏ hệ thống của Android vẫn hiện trên
  màn hình điện thoại, con trỏ PC vẽ theo (cùng vị trí) — không lệch.
- Lăn ngang (horizontal wheel) chưa hỗ trợ — chuột gắn điện thoại hiếm
  có; cần thì thêm `'scroll'` ngang sau.
- `MouseConnection.start()` là static idempotent; gọi từ
  `_RemotePageState.initState` (chỉ màn remote cần biết có chuột).
