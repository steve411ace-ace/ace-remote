# Bước 41 — Bật trackpad thì mặc định ẩn phím Left/Right

## Yêu cầu (An, 14/11 20:01)

"Em làm thêm cho anh điều kiện nếu bật trackpad thì mặc định là ẩn
left right"

## Thiết kế

- Trong màn hình Sửa kết nối, bật công tắc "Vùng trackpad" thì mức
  "Phím Left/Right" tự chuyển sang **Ẩn cả 2** (radio cập nhật ngay
  trên màn hình sửa, lưu cùng lúc với trackpad).
- Đây chỉ là **mặc định**: chạm vùng trackpad là click trái, chạm 2
  ngón là click phải nên 2 phím Left/Right thừa, Space được dài ra.
  Anh vẫn chọn lại "Hiện cả 2" (hoặc "Ẩn Right") trong mục Phím
  Left/Right nếu muốn có phím trở lại — lựa chọn sau đó được giữ.
- Tắt trackpad thì không đụng tới mức Phím Left/Right (giữ nguyên
  mức đang chọn).
- Không đổi model/store: mức ẩn vẫn lưu trong `clickKeys` như bước 36.

## Kiểm chứng

- Local: `flutter analyze` 0 issue, `flutter test` pass (2 test mới:
  bật trackpad → lưu ra `clickKeys` hideBoth; bật trackpad rồi chọn
  "Hiện cả 2" → lưu ra showBoth, trackpad vẫn bật).
- Kiểm chứng thật trên máy (An): mở Sửa kết nối, bật "Vùng trackpad"
  → mục Phím Left/Right tự nhảy sang "Ẩn cả 2"; nối RDP thấy Space
  dài, không còn 2 phím Left/Right.

## Phiên bản

- 1.5.9+26, commit VM + PC (xem git log), CI run #26.
- Lưu ý: run #25 (1.5.8, bước 40) đang build thì An gửi yêu cầu này,
  nên bước 41 chờ run #25 xong mới push để không hủy run đang chạy.
