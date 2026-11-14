# Bước 36 — Config phím Left/Right 3 mức, chỉnh tay (thay hẳn tự ẩn)

## Yêu cầu (An, 14/11 15:51)

"Hay em làm config bật tắt các nút này chung chỗ với config trackpad, bàn
phím đi. Config left right này Sẽ có 3 mức: Ẩn right, ẩn cả 2, hiện cả 2"

An chọn "Thay hẳn, chỉnh tay thôi" (15:52): config này thay hẳn việc tự
ẩn theo chuột — chuột cắm vào không còn ảnh hưởng gì tới 2 phím nữa.

## Thiết kế

- **Model** (`lib/rdp_connections.dart`): enum `ClickKeys` với 3 giá trị
  `showBoth` / `hideRight` / `hideBoth`, lưu trong JSON record dưới key
  `clickKeys` (dạng string). Record cũ không có key → mặc định `showBoth`.
  Mặc định này giữ đúng hành vi trước bước 34 (hiện cả 2 phím).
- **Màn hình Sửa kết nối** (`lib/main.dart`, `_ConnectionEditorPage`):
  mục "Phím Left/Right" ngay dưới 2 công tắc Trackpad / Hiện bàn phím,
  3 `RadioListTile`:
  - Hiện cả 2 — hiện cả phím Left và Right hai bên phím Space.
  - Ẩn Right — chỉ ẩn phím Right, phím Space dài thêm.
  - Ẩn cả 2 — ẩn cả hai phím, phím Space dài nhất.
- **Bàn phím** (`keyboardPanel()`): đọc `widget.rdpConnection?.clickKeys`
  (null → `showBoth`). RDP mode: `hideLeft` khi `hideBoth`, `hideRight`
  khi khác `showBoth`; Space = `spaceU` + chiều rộng mỗi phím bị ẩn.
  Agent mode luôn hiện cả 2 như trước. Bỏ `ValueListenableBuilder` bọc
  ngoài `keyboardPanel()` — không còn trạng thái chuột để nghe nữa.
- **Xóa tự ẩn** (phần code bước 34/35 không còn ai dùng):
  - Dart: xóa class `MouseConnection` (`lib/rdp_surface.dart`) và lời gọi
    `MouseConnection.start()` trong `_RemotePageState.initState`.
  - Native (`RdpPlugin.kt`): xóa channel `vn.aceremote.app/input`,
    `InputDeviceListener`, `isMouseConnected()` (kèm bản sửa isExternal
    của bước 35 — chưa từng lên bản phát hành) và import `InputManager`.
  - Giữ nguyên: chuột vẫn lái con trỏ PC qua channel `mouseMove` /
    `mouseButton` của `RdpController`, và đường chạm native vẫn bỏ qua
    event chuột (`isFromSource(SOURCE_MOUSE)`) để click không bắn 2 lần.
- **Widget** (`AceRemoteWidgetProvider.kt`): thêm field `clickKeys` vào
  data class `Conn` (đọc + ghi lại). Widget không đổi setting này, nhưng
  `saveConnections` ghi lại toàn bộ JSON — thiếu field này thì mỗi lần bấm
  nút widget sẽ xóa mất setting.

## Kiểm chứng

- Local: `flutter analyze` 0 issue, `flutter test` pass (test bước 34
  viết lại theo config; thêm test round-trip JSON + mặc định record cũ).
- Kiểm chứng thật trên máy (An): vào Sửa kết nối của ace → chọn từng mức
  → nối RDP → xem phím Left/Right và độ dài Space đúng từng mức; chọn
  "Hiện cả 2" rồi cắm chuột vào → 2 phím vẫn hiện (không tự ẩn nữa).

## Phiên bản

- 1.5.4+21 (cùng bản với bước 35 — bước 35 chưa đẩy lên nên gộp chung),
  commit VM + PC (xem git log), CI run #21.
