# Bước 47 — Đồng bộ clipboard PC ↔ điện thoại (chữ)

## Yêu cầu (An, 14/11 22:06, mục 4 trong 4 cải tiến)

Copy trên điện thoại thì paste được trên PC và ngược lại.

## Phát hiện quan trọng khi nghiên cứu

Hóa ra phần nặng đã có sẵn trong FreeRDP, app chỉ chưa nối dây:

- `LibFreeRDP.setConnectionInfo()` (app gọi sẵn trong
  `RdpPlugin.kt`) tự thêm cờ `/clipboard` KHÔNG điều kiện, nên
  kênh cliprdr native đã bật từ lâu.
- `android_cliprdr.c` đã nằm trong CMakeLists của freeRDPCore
  (được biên dịch vào `libfreerdp-android.so`).
- FreeRDP có sẵn 2 đầu API Java: `LibFreeRDP.sendClipboardData(inst,
  text)` (gửi chữ lên PC) và callback
  `UIEventListener.OnRemoteClipboardChanged(data)` (PC đổi clipboard).
- aFreeRDP mẫu làm đúng như vậy qua `ClipboardManagerProxy` +
  `SessionActivity`.

## Thay đổi (chỉ Kotlin native, `RdpPlugin.kt`)

- `OnRemoteClipboardChanged(data)`: ghi chữ vào clipboard Android
  (qua `ClipboardManager`, trên main thread). Có chặn dội lại:
  ghi nhớ `lastRemoteText`, listener phía điện thoại bỏ qua lần
  đổi clipboard trùng đúng nội dung vừa nhận từ PC (máy chủ chỉ
  báo khi nội dung đổi nên vòng dội tối đa cũng chỉ 1 lần).
- Listener `OnPrimaryClipChangedListener` đăng ký lúc tạo view,
  gỡ lúc `dispose()`: khi clipboard điện thoại đổi mà đang nối
  RDP thì gọi `sendClipboardData(handle, text)`.
- Lúc nối thành công (`OnConnectionSuccess`): đẩy một lần nội dung
  clipboard hiện tại của điện thoại sang PC (như
  `getPrimaryClipManually()` của aFreeRDP) — cái gì đã copy trước
  lúc nối thì paste được luôn, không cần copy lại.
- Chỉ chữ: `OnRemoteClipboardImageChanged` vẫn bỏ trống, clipboard
  ảnh trên điện thoại cũng bỏ qua (item không có text). Ảnh là việc
  nối thêm sau nếu An cần (cần ContentProvider cho ảnh).

## Kiểm chứng

- Local: `flutter analyze` 0 issue, `flutter test` pass 109/109
  (bước này chỉ đổi Kotlin nên không có test Dart nào bao phủ).
  Biên dịch Kotlin do CI kiểm (VM không build được).
- Kiểm chứng thật trên máy (An): nối RDP vào PC ace, copy một dòng
  chữ trên PC (Ctrl+C) rồi paste trên điện thoại (nhấn giữ → Dán);
  copy trên điện thoại rồi Ctrl+V trên PC. Cả 2 chiều đều phải
  sang ngay. Kiểm tra thêm: nối lại khi điện thoại đã có sẵn chữ
  trong clipboard thì paste được trên PC không cần copy lại.

## Phiên bản

- 1.5.15+32, commit VM + PC (xem git log), CI run #31.
- Lưu ý: làm xong trong lúc run #30 (bước 46) đang build nên chờ
  run #30 xong mới push.
