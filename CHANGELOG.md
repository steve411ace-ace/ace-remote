# Changelog — Ace Remote

Quy tắc (theo cách Thuốc Vui: mỗi bản tăng cả versionName và build number
trong `pubspec.yaml`): mỗi bản lên App Tester phải tăng `version:` trong
`pubspec.yaml` và thêm một mục mới ở ĐẦU file này. CI lấy mục mới nhất làm
release notes trên Firebase App Distribution (xem `scripts/release_notes.py`),
và chặn build nếu quên tăng version (xem `scripts/check_version.py`).

## [1.5.13+30] - 2026-11-14

- Ẩn con trỏ hệ thống Android trên màn hình remote: cắm chuột rời vào
  không còn 2 con trỏ chồng nhau (mũi tên Android + con trỏ PC), chỉ
  còn con trỏ PC. Vùng bàn phím vẫn giữ mũi tên Android vì ở đó
  không có con trỏ PC.

## [1.5.12+29] - 2026-11-14

- Miếng trackpad thu hẹp thêm 5% (40% → 35% chiều rộng dải, tỉ lệ
  Dell XPS) cho cân đối hơn. An chốt 35% sau khi xem hình so sánh
  40% với 35% cùng tỉ lệ.

## [1.5.11+28] - 2026-11-14

- Cả bàn phím giờ như phím laptop thật: mỗi phím có độ bóng nhẹ (trên
  sáng hơn, dưới tối hơn như ánh sáng chiếu xuống) + bóng đổ mềm nâng
  phím khỏi mặt bàn phím; phím đang bấm thì mất bóng (cảm giác nhấn
  xuống). Tông màu mỗi trạng thái giữ nguyên.
- Gồm cả màu bóng trackpad ở 1.5.10 (gradient + bóng đổ mềm).

## [1.5.10+27] - 2026-11-14

- Miếng trackpad thêm màu bóng như trackpad thật trong ảnh: gradient
  dọc nhẹ (trên sáng hơn, dưới tối hơn như ánh sáng chiếu xuống) +
  bóng đổ mềm nâng miếng trackpad khỏi mặt bàn phím. Tông xám trung
  bình giữ nguyên.

## [1.5.9+26] - 2026-11-14

- Bật "Vùng trackpad" thì phím Left/Right mặc định ẩn (chạm vùng là
  click trái, chạm 2 ngón là click phải nên 2 phím thừa, Space được
  dài ra). Đây chỉ là mặc định: anh vẫn chọn lại "Hiện cả 2" trong
  mục Phím Left/Right nếu muốn.

## [1.5.8+25] - 2026-11-14

- Trackpad xám thu hẹp cho đúng tỉ lệ laptop thật: rộng 40% dải bàn
  phím (tỉ lệ MacBook, trước là 60% trông như thanh ngang), bo góc
  giảm 16 xuống 8 (bo nhẹ như trackpad laptop, trước trông như viên
  thuốc). Vùng cảm ứng vẫn full chiều ngang như cũ.

## [1.5.7+24] - 2026-11-14

- Vùng trackpad giờ là miếng xám bo tròn nằm giữa như ảnh anh gửi
  (trackpad laptop nằm giữa phần kê tay): rộng 60% dải bàn phím, căn
  giữa, màu xám rõ trên nền đen. Vùng cảm ứng vẫn full chiều ngang
  như cũ, kéo/chạm ở đâu trên dải cũng di chuột/click được.

## [1.5.6+23] - 2026-11-14

- Vùng trackpad bo tròn cho giống trackpad laptop (góc bo 16, không còn
  icon ở giữa, tách khỏi dãy phím bằng khe 6px như phần kê tay). Vùng vẫn
  full chiều ngang, bằng đúng chiều rộng dãy phím.

## [1.5.5+22] - 2026-11-14

- Thêm config "Vùng trackpad" trong màn hình Sửa kết nối: chỉ khi mở màn
  hình ra mới có vùng cảm ứng dưới bàn phím để di chuột (kéo = di chuột,
  chạm = click trái, chạm 2 ngón = click phải, kéo 2 ngón = cuộn). Màn hình
  remote giữ nguyên, dãy phím nhỏ lại để chừa chỗ cho vùng trackpad. Khi
  gập màn hình lại thì vùng này ẩn đi, bàn phím về như cũ.

## [1.5.4+21] - 2026-11-14

- Phím Left/Right giờ chỉnh tay trong màn hình Sửa kết nối, chung chỗ với
  công tắc Trackpad và Hiện bàn phím, 3 mức: Hiện cả 2, Ẩn Right, Ẩn cả 2.
  Phím nào ẩn thì phím Space dài thêm đúng bằng chiều rộng phím đó. Việc tự
  ẩn theo chuột cắm vào đã bỏ hẳn: bản 1.5.3 ẩn mất 2 phím ngay cả khi chưa
  cắm chuột, vì cách nhận biết cũ đếm cả bộ nhận bút S Pen gắn sẵn trong
  máy. Mặc định là Hiện cả 2.

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
