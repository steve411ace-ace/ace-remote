# Bước 46 — Giữ phím để lặp như bàn phím thật

## Yêu cầu (An, 14/11 22:06, mục 3 trong 4 cải tiến)

Bàn phím thật: giữ Backspace thì xóa liên tục, giữ mũi tên thì di
chuyển liên tục. Bàn phím app trước giờ bấm 1 cái chỉ gửi 1 phím.

## Thay đổi (chỉ Dart, `KeyboardSurface` trong `lib/main.dart`)

- Giữ một phím 500ms thì bắt đầu lặp, mỗi 50ms gửi lại phím đó
  (nhịp typematic quen thuộc). Nhả ra thì dừng, không gửi thêm phát
  nào — vì với giữ trên 500ms, nhánh `dragging` đã chặn sẵn phát
  bấm lúc nhả (hành vi có sẵn).
- Không lặp: Shift/Ctrl/Alt/Win (bật/tắt modifier), Caps (toggle),
  2 phím Left/Right và 'Click trái'/'Click phải' (đó là click chuột).
- Chỉ ở chế độ RDP: ở chế độ agent, giữ 500ms là bắt đầu kéo chuột
  (hành vi có sẵn), nên repeat tắt ở đó. `trackpad()` truyền
  `repeatKeys: widget.rdpMode` và `labelAt` (tra cứu nhãn phím) vào
  `KeyboardSurface`.
- `keyLabelAt()` tách ra từ code tra cứu trong `onPressed` để highlight
  và kiểm tra lặp dùng chung một chỗ.

## Kiểm chứng

- Local: `flutter analyze` 0 issue, `flutter test` pass (test mới:
  giữ Backspace 700ms → đúng 5 lần bấm = 10 lệnh key, nhả ra không
  thêm; bấm nhanh vẫn đúng 1 lần; giữ Shift không gửi phím nào).
  Bẫy test đã sửa: `pumpAndSettle()` mặc định cộng 100ms mỗi lần
  pump nên làm lệch đếm thời gian — sau khi giữ phải dùng pump
  không thời gian để xả hàng đợi gửi phím.
- Kiểm chứng thật trên máy (An): nối RDP, giữ Backspace → xóa liên
  tục; giữ mũi tên → con trỏ di chuyển liên tục; giữ Shift không
  lặp; bấm nhanh vẫn gõ 1 ký tự.

## Phiên bản

- 1.5.14+31, commit VM + PC (xem git log), CI run #30.
- Lưu ý: làm xong trong lúc run #29 (bước 45) đang build nên chờ
  run #29 xong mới push.
