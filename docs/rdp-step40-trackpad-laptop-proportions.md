# Bước 40 — Trackpad đúng tỉ lệ laptop (hẹp lại + bo nhẹ)

## Yêu cầu (An, 14/11 19:56–19:58, kèm ảnh chụp màn hình bản 1.5.7)

"Bo trackpad rộng quá em ơi, ko phù hợp" + "Em làm độ rộng cho phù
hợp, nhìn như laptop thiệt nha"

Ảnh chụp cho thấy miếng trackpad 60% trông như thanh ngang bo tròn
kiểu viên thuốc, không giống trackpad laptop.

## Thay đổi (chỉ giao diện, không đổi hành vi)

- Rộng: 60% → **40%** dải bàn phím. Trackpad laptop thật chỉ rộng
  khoảng 32–40% thân máy (MacBook ~40%, XPS ~36%, ThinkPad ~32%),
  nên 60% là quá rộng so với laptop thật.
- Bo góc: 16 → **8**. Trackpad laptop thật chỉ bo nhẹ; bo 16 trên
  miếng lùn làm nó trông như viên thuốc.
- Màu xám, căn giữa, khe 6px, vùng cảm ứng full ngang: không đổi.

## Kiểm chứng

- Local: `flutter analyze` 0 issue, `flutter test` pass (test bước 37
  cập nhật: miếng xám rộng ~317px ở màn 800px, căn giữa, bo 8).
- Kiểm chứng thật trên máy (An): mở màn hình ra, bật "Vùng trackpad"
  → miếng xám hẹp lại, bo nhẹ, nhìn như trackpad laptop thật.

## Phiên bản

- 1.5.8+25, commit VM + PC (xem git log), CI run #25.
