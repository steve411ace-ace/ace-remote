# Bước 38 — Bo tròn vùng trackpad cho giống laptop

## Yêu cầu (An, 14/11 19:13)

"Anh thấy có rồi, em làm khoản bo tròn cho đẹp, cho giống laptop đi em.
Vùng trackpad vẫn full màn hình nha"

## Thay đổi (chỉ giao diện, không đổi hành vi)

- Góc bo của vùng trackpad: 12 → **16**, giống trackpad laptop.
- Bỏ icon cảm ứng ở giữa — trackpad thật không có icon, để trống cho
  giống.
- Thêm khe 6px giữa dãy phím và vùng trackpad (như phần kê tay trên
  laptop); dãy phím nhường 1px mỗi hàng cho khe này.
- Vùng trackpad **vẫn full chiều ngang**, rộng đúng bằng dãy phím
  (không thu hẹp, không bo thành viên nổi).

## Kiểm chứng

- Local: `flutter analyze` 0 issue, `flutter test` pass (test bước 37
  cập nhật: hàng phím lùn hơn 1px vì khe 6px; thêm assert vùng rộng
  792px ở màn 800px, bo góc 16, không còn icon).
- Kiểm chứng thật trên máy (An): mở màn hình ra, bật "Vùng trackpad"
  → vùng bo tròn, trống, full ngang, tách khỏi phím bằng khe nhỏ.

## Phiên bản

- 1.5.6+23, commit VM + PC (xem git log), CI run #23.
