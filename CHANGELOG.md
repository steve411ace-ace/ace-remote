# Changelog — Ace Remote

Quy tắc (theo cách Thuốc Vui: mỗi bản tăng cả versionName và build number
trong `pubspec.yaml`): mỗi bản lên App Tester phải tăng `version:` trong
`pubspec.yaml` và thêm một mục mới ở ĐẦU file này. CI lấy mục mới nhất làm
release notes trên Firebase App Distribution (xem `scripts/release_notes.py`),
và chặn build nếu quên tăng version (xem `scripts/check_version.py`).

## [1.5.3+20] - 2026-11-14

- Chuột rời cắm vào điện thoại giờ điều khiển được chuột máy tính trong
  phiên RDP, chỉ trên phần màn hình PC (di chuột = di chuột PC, click
  trái/phải/giữa, lăn chuột để cuộn). Trước đây chuột chỉ vào như chạm:
  click thành chạm, không di được khi không bấm, không có click phải và
  không lăn được. Khi có chuột cắm vào, 2 phím Left/Right trên bàn phím
  ẩn đi và phím Space dài ra (chuột đã có nút thật rồi); rút chuột ra thì
  2 phím hiện lại.

## [1.5.2+19] - 2026-11-14

- Widget: vẽ lại icon nút "Bàn phím" dạng outline (cùng style với icon
  Trackpad — viền + 3 phím + phím Space). Icon cũ là hình đặc của Material,
  lỗ phím chỉ 2×2 nên ở cỡ 18dp các lỗ biến mất, nhìn thành một cục mờ
  không rõ là bàn phím.

## [1.5.1+18] - 2026-11-14

- Widget: bo góc ngoài 28dp đều + viền 1dp (chuẩn Thuốc Vui — trước đây bitmap
  nền cố định 400×200 bị kéo giãn không đều nên góc bo thành ellipse); chạm
  bất cứ đâu ngoài 3 nút đều mở app và kết nối (trước đây chạm không mở được
  vì dùng intent ACTION_VIEW không resolve); app đọc lại dữ liệu mỗi khi mở
  nên bấm nút trên widget xong vào app là thấy đổi theo ngay.

## [1.5.0+16] - 2026-11-14

- Phiên bản tăng lên 1.5.0 (16): sửa cách đánh phiên bản — mỗi bản build giờ
  có số phiên bản mới, không còn 1.4.0 (5) mãi như 11 bản trước (runs #5–#15).
- Release notes chi tiết: mỗi bản lên App Tester kèm danh sách thay đổi lấy
  từ mục mới nhất của CHANGELOG này (trước đây chỉ có một dòng chung chung).
- CI kiểm tra: build sẽ lỗi nếu quên tăng version trong `pubspec.yaml`
  (so với commit trước) hoặc build number không tăng.
- Cài đặt hiện số phiên bản của app đang cài (ví dụ "Phiên bản 1.5.0 (16)"),
  để kiểm tra đúng bản đã cài hay chưa.
- Widget màn hình chính: 3 nút Trackpad, Bàn phím, chuyển đổi giờ bấm là đổi
  ngay trên widget, không mở app nữa (xử lý native trong Kotlin); bỏ nút
  "Kết nối" (chạm vào tên máy là kết nối); làm đẹp lại toàn bộ widget theo
  Material 3 (icon tile xanh ngọc, nút chuyển hình tròn với icon mũi tên đổi
  chỗ, pill rõ trạng thái bật/tắt).
- Cập nhật tại chỗ (theo cách Thuốc Vui): khóa ký debug cố định được commit
  trong repo dạng base64 nên mọi bản build cùng 1 chữ ký — từ bản này về sau
  bấm "Cập nhật" trên App Tester là được, không cần gỡ/cài, không mất kết nối
  đã lưu. Lưu ý: bản này vẫn phải gỡ/cài 1 lần cuối vì đổi chữ ký so với các
  bản trước (ký bằng debug key ngẫu nhiên của từng máy build).

## [1.4.0+5] - 2026-11-13

- Bản RDP-only (branch rdp-prototype, runs #5–#15, bước 19–27): làm lại
  Ace Remote bằng RDP (FreeRDP 3.33.0) thay cho agent-mode cũ.
- Kết nối RDP thật, lưu user/pass mã hóa, nhiều kết nối đã lưu (bấm là nối,
  long-press: Kết nối/Yêu thích/Sửa/Xóa), tự nối lại khi mở lại từ đa nhiệm.
- Bàn phím laptop 6 hàng: phím Left/Right chuột 2 bên Space, Shift đổi nhãn
  phím (2 thành @), Caps Lock bật/tắt thật, mũi tên chữ T ngược, cột
  PgUp/PgDn/Home/End, hàng F (Delete to, F1–F12 bằng phím số).
- Trackpad lướt trên bàn phím, con trỏ chuột hiện rõ, ẩn/hiện bàn phím.
- Cài đặt Sáng/Tối/Theo điện thoại; loading kết nối hiện đại.
- Widget màn hình chính 4x2: sáng/tối theo app, chỉnh độ trong suốt 0–100%,
  nút nhanh Trackpad/bàn phím, chuyển đổi giữa các kết nối, chạm để kết nối.
