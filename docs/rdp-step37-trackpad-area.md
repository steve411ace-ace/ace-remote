# Bước 37 — Vùng trackpad dưới bàn phím (chỉ khi mở màn hình ra)

## Yêu cầu (An, 14/11 18:30–18:31, kèm ảnh điện thoại gập mở như laptop)

"Em cho thêm config đi em (chỉ với chế độ mở màn hình ra mới có). Màn
hình remote vẫn giữ nguyên, bật tắt trackpad dãy phím sẽ nhỏ lại" +
"Thêm config mới nha. Vùng trackpad"

## Thiết kế

- **Model** (`lib/rdp_connections.dart`): `trackpadArea` bool, lưu trong
  JSON record dưới key `trackpadArea`, mặc định false. Record cũ không có
  key → false.
- **Màn hình Sửa kết nối**: công tắc "Vùng trackpad" ngay dưới "Hiện bàn
  phím", ghi chú: chỉ khi mở màn hình ra mới có tác dụng, màn hình remote
  không đổi.
- **Hiển thị** (`keyboardPanel()`): vùng này chỉ hiện khi cả 3 điều kiện
  đúng — RDP mode, connection bật `trackpadArea`, và màn hình rộng
  (`maxWidth >= 600`, tức mở ra; gập lại ~378px thì ẩn). Chiều cao dải
  bàn phím KHÔNG đổi (remote giữ nguyên): vùng trackpad cao bằng 1.5 hàng
  phím thường, 6 hàng phím chia phần còn lại nên mỗi phím lùn đi (ở màn
  mở ~800px: hàng phím từ ~56.6px xuống ~42.4px). Agent mode không có
  vùng này (config nằm trên RdpConnection).
- **Hành vi**: vùng này là một `GestureDetector` + nằm trong `Listener`
  `keyboardSwipe` bọc ngoài bàn phím, nên nó dùng chung đường xử lý với
  lướt trên phím: kéo 1 ngón = di chuột tương đối (`moveRelative`),
  kéo 2 ngón = cuộn, chạm 2 ngón = click phải. Riêng chạm 1 ngón = click
  trái tại vị trí con trỏ (`clickAtLastPosition('left')`) — trên vùng
  này không có phím nào nên chạm không gõ nhầm được. Vùng trackpad làm
  việc độc lập với công tắc "Chế độ Trackpad" (công tắc đó chỉ điều khiển
  việc lướt TRÊN CÁC PHÍM có di chuột hay không).
- **Giao diện**: hình chữ nhật bo góc, nền nhạt hơn bàn phím một chút
  (`#1e1f23` trên nền `#16171a`), viền mờ, icon cảm ứng mờ ở giữa làm
  dấu hiệu.
- **Widget** (`AceRemoteWidgetProvider.kt`): thêm field `trackpadArea`
  vào data class `Conn` (đọc + ghi lại) để nút widget không xóa mất
  setting khi ghi lại JSON — giống `clickKeys` ở bước 36.

## Kiểm chứng

- Local: `flutter analyze` 0 issue, `flutter test` pass (test mới: vùng
  hiện/ẩn theo cấu hình + gập/mở, hàng phím lùn đi khi bật, chạm vùng =
  click trái, kéo vùng = moveRelative).
- Kiểm chứng thật trên máy (An): mở màn hình ra, bật "Vùng trackpad"
  trong Sửa kết nối → nối RDP → vùng trackpad hiện dưới bàn phím, phím
  lùn lại, remote không đổi; kéo vùng để di chuột, chạm để click trái;
  gập màn hình lại → vùng ẩn, phím về như cũ.

## Phiên bản

- 1.5.5+22, commit VM + PC (xem git log), CI run #22.
