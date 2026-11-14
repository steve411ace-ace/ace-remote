# Bước 48 — Thanh trượt chỉnh độ nhạy trackpad

## Yêu cầu (An, 14/11 22:06, mục 5 trong 4 cải tiến)

Chỉnh được con trỏ di nhanh hay chậm theo tay kéo.

## Hiện trạng trước bước này

Độ nhạy là hằng số `TRACKPAD_SENSITIVITY = 1.5f` trong
`RdpPlugin.kt`, áp dụng cho MỌI lần di chuột tương đối qua hàm
`moveCursorRelative` — cả 3 đường kéo: chế độ Trackpad trên màn
hình remote, lướt trên bàn phím, và dải trackpad. Chuột rời (di
tuyệt đối) không qua đây nên không bị ảnh hưởng.

## Thay đổi

- Model: `trackpadSensitivity` (double, mặc định 1.5) trên
  `RdpConnection` — constructor, `copyWith`, `toJson`/`fromJson`
  (bản ghi cũ thiếu key → 1.5), `RdpConnectionStore.add`. Widget
  Kotlin `Conn` cũng mang thêm field này (bài học bước 29: field
  nào nằm trong JSON record thì Kotlin phải mang theo, không thì
  nút widget ghi lại sẽ xóa mất).
- Editor: thanh trượt "Độ nhạy trackpad" ngay dưới công tắc "Vùng
  trackpad" — 0.5×–3.0×, 10 nấc (mỗi nấc 0.25×), hiển thị giá trị
  hiện tại (vd 1.50×). 0.5× chậm và chính xác, 3.0× lướt hết màn
  hình trong một lần kéo.
- Đường truyền xuống native: `RdpController.setTrackpadSensitivity`
  (kẹp 0.5–3.0, không gửi lại nếu giá trị không đổi) + gửi kèm
  trong lệnh channel `'mode'` (`{'trackpad': ..., 'sensitivity':
  ...}`); `attach()` gửi lại giá trị hiện tại như với chế độ
  trackpad. `RdpConnectionPane` gọi khi mở kết nối.
- Native: hằng số thành biến `trackpadSensitivity`, nhận từ lệnh
  `'mode'` (kẹp 0.5–3.0), `moveCursorRelative` dùng biến này.

## Kiểm chứng

- Local: `flutter analyze` 0 issue, `flutter test` pass (test mới:
  round-trip + mặc định 1.5 cho bản ghi cũ; lệnh mode mang
  sensitivity, không gửi lại khi trùng, kẹp giá trị ngoài khoảng;
  kéo slider trong editor tới tối đa rồi lưu → 3.0 được ghi).
  Bẫy test đã sửa: slider nằm ngoài cache extent của ListView
  nên phải kéo list xuống trước khi tìm, và một test cũ assert
  đúng nội dung lệnh `'mode'` phải thêm key sensitivity.
  Biên dịch Kotlin do CI kiểm (VM không build được).
- Kiểm chứng thật trên máy (An): mở Sửa kết nối → kéo thanh
  trượt xuống 0.5× → nối lại, kéo trackpad thấy con trỏ đi chậm
  và chính xác; kéo lên 3.0× → một lần kéo là qua hết màn hình.
  Mỗi kết nối nhớ mức riêng.

## Phiên bản

- 1.5.16+33, commit VM + PC (xem git log), CI run #32.
- Lưu ý: làm xong trong lúc run #30 (bước 46) đang build nên chờ
  run #30 xong mới push — push gộp bước 47 + 48 (2 commit, 1 run,
  theo tiền lệ bước 42+43).
