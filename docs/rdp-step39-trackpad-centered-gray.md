# Bước 39 — Trackpad xám bo tròn nằm giữa (như ảnh anh gửi)

## Yêu cầu (An, 14/11 19:38)

"Ý anh là bo phần trackpad màu xám ở giữa như hình anh gửi đó em"

Anh xem lại ảnh: điện thoại gập mở như laptop mini, dưới bàn phím là
một miếng trackpad màu xám, bo tròn, nằm GIỮA phần kê tay — không phải
full ngang. Bước 38 em hiểu sai (bo cả dải full ngang), bước này sửa
lại theo đúng ảnh.

## Thay đổi

- Miếng trackpad nhìn thấy: hình chữ nhật xám (`#3a3b40`, rõ xám trên
  nền đen `#16171a`), bo góc 16, rộng 60% dải bàn phím, căn giữa, cao
  bằng dải trackpad như cũ. Không còn icon.
- Vùng cảm ứng vẫn là cả dải full ngang như anh dặn trước đó ("vẫn
  full màn hình"): kéo/chạm ở bất cứ đâu trên dải — kể cả phần đen hai
  bên miếng xám — đều di chuột/click được. Chỉ phần nhìn thấy là thu
  vào giữa, phần dùng thì vẫn full.
- Khe 6px trên miếng trackpad, dãy phím, màn hình remote: không đổi.

## Kiểm chứng

- Local: `flutter analyze` 0 issue, `flutter test` pass (test bước 37
  cập nhật: miếng xám rộng ~475px ở màn 800px, căn giữa, bo 16, màu
  xám; vùng cảm ứng vẫn rộng 792px).
- Kiểm chứng thật trên máy (An): mở màn hình ra, bật "Vùng trackpad"
  → miếng xám bo tròn nằm giữa như ảnh, kéo/chạm trên dải vẫn di
  chuột/click được.

## Phiên bản

- 1.5.7+24, commit VM + PC (xem git log), CI run #24.
