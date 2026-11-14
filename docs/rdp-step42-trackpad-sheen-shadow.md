# Bước 42 — Màu bóng trackpad như ảnh thật

## Yêu cầu (An, 14/11 20:14)

"Mà màu bóng trackpad chưa đẹp giống thiệt như hình a gửi"

Miếng trackpad bản 1.5.8 là màu xám phẳng một màu (#3a3b40). Trackpad
trong ảnh anh gửi không phẳng: nó có độ bóng nhẹ (trên sáng hơn, dưới
tối hơn như ánh sáng chiếu xuống) và bóng đổ mềm nâng nó khỏi mặt kê
tay.

## Thay đổi (chỉ giao diện, không đổi hành vi)

- Gradient dọc nhẹ: trên `#48494f` → dưới `#343539` (tông xám trung
  bình giữ nguyên như trước).
- Bóng đổ mềm: đen 40%, blur 8, lệch xuống 2px — nâng miếng trackpad
  khỏi mặt bàn phím.
- Bo góc 8, rộng 40%, căn giữa, khe 6px, vùng cảm ứng full ngang:
  không đổi.

## Kiểm chứng

- Local: `flutter analyze` 0 issue, `flutter test` pass (test bước 37
  cập nhật: miếng xám có gradient 2 màu + 1 bóng đổ, không còn màu
  phẳng).
- Kiểm chứng thật trên máy (An): mở màn hình ra, bật "Vùng trackpad"
  → miếng trackpad có độ bóng nhẹ + bóng đổ như trackpad thật.

## Phiên bản

- 1.5.10+27, commit VM + PC (xem git log), CI run #27.
- Lưu ý: run #26 (1.5.9, bước 41) đang build thì An gửi yêu cầu này,
  nên bước 42 chờ run #26 xong mới push để không hủy run đang chạy.
