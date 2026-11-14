# Bước 35 — Sửa nhận biết chuột: chỉ đếm thiết bị gắn ngoài

> ĐÃ BỊ THAY THẾ bởi bước 36 (An chọn "Thay hẳn, chỉnh tay thôi"): việc
> nhận biết chuột đã bỏ hẳn, nên bản sửa isExternal dưới đây KHÔNG BAO GIỜ
> lên bản phát hành nào. Giữ lại file này làm hồ sơ vì nó ghi đúng nguyên
> nhân lỗi của bản 1.5.3 và cách trả lời câu hỏi "em dùng cách nào để nhận
> biết có chuột" của An.

## Vấn đề (An báo 14/11 15:47, kèm ảnh)

- An chưa cắm chuột vào điện thoại nhưng 2 phím Left/Right trên bàn phím đã
  bị ẩn, phím Space đã dài ra — app tưởng là đang có chuột.
- Ảnh An gửi: màn hình RDP đang ở màn hình khóa Windows ("Other user",
  "Welcome"), hàng phím dưới cùng chỉ còn Ctrl / Win / Alt / Space (dài) /
  Alt / Ctrl / ← / ↓ / → — không còn 2 phím Left/Right.

## Cách nhận biết chuột (trả lời câu hỏi của An)

App không hỏi hệ thống "có chuột không" bằng một câu duy nhất. Nó làm 2 việc:

1. **Hỏi lúc mở app** (`isMouseConnected`): liệt kê tất cả thiết bị nhập
   liệu của Android (`InputManager.inputDeviceIds`) và xem có thiết bị nào
   báo là chuột không (`InputDevice.supportsSource(SOURCE_MOUSE)`).
2. **Nghe thay đổi** (`InputManager.InputDeviceListener`): mỗi lần có thiết
   bị được thêm/bớt/đổi, kiểm tra lại và đẩy trạng thái mới sang Dart qua
   channel `vn.aceremote.app/input` (`mouseChanged`).

Dart giữ trạng thái trong `MouseConnection.connected` (ValueNotifier) và
bàn phím ẩn/hiện 2 phím Left/Right theo đó.

## Nguyên nhân lỗi

Bước 34 kiểm tra quá rộng: nó đếm **mọi** thiết bị báo `SOURCE_MOUSE`,
kể cả thiết bị **gắn sẵn trong máy**. Trên Fold6, bộ nhận bút S Pen gắn
sẵn trong màn hình luôn nằm trong danh sách thiết bị nhập liệu và cũng báo
là chuột — nên app luôn thấy "có chuột" ngay từ đầu, dù An chưa cắm gì.

## Sửa (chỉ native, `RdpPlugin.kt`)

`isMouseConnected()` giờ yêu cầu thêm `device.isExternal` (API 29+,
minSdk của app là 29 nên dùng được):

- `isExternal == true` với chuột USB/Bluetooth gắn ngoài → tính là chuột.
- `isExternal == false` với thiết bị gắn sẵn trong máy (bộ nhận S Pen,
  màn hình cảm ứng, phím cứng) → không tính.

Sửa này đúng bất kể thiết bị gắn sẵn nào gây ra lỗi, vì mọi thiết bị gắn
sẵn đều bị loại. Kèm log debug `AceRdp` liệt kê từng thiết bị ứng cử viên
(id, tên, external) để lần sau chẩn đoán được ngay bằng logcat.

Đường chạm native vẫn bỏ qua event chuột (`isFromSource(SOURCE_MOUSE)`)
như bước 34 — không đổi.

## Kiểm chứng

- Local: `flutter analyze` 0 issue, `flutter test` pass.
- Kiểm chứng thật trên máy: cần An test trên Fold6 (phần native không
  test được bằng unit test trên VM):
  1. Chưa cắm chuột → 2 phím Left/Right hiện, Space ngắn như cũ.
  2. Cắm chuột Bluetooth → 2 phím ẩn, Space dài ra, di chuột lái con trỏ PC.
  3. Rút chuột → 2 phím hiện lại.

## Phiên bản

- 1.5.4+21, commit VM + PC (xem git log), CI run #21.
