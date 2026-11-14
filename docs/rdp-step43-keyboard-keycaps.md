# Bước 43 — Phím bấm như phím laptop thật

## Yêu cầu (An, 14/11 20:20)

"Cả bàn phím luôn nha em. Làm cho giống thật nhất nha em"

Sau trackpad (bước 42), An muốn cả bàn phím cũng giống thật: phím
laptop thật không phẳng — mỗi phím có độ bóng nhẹ và bóng đổ mềm.

## Thay đổi (chỉ giao diện, không đổi hành vi)

- Mỗi phím (`laptopKey`, cả RDP mode lẫn agent mode): gradient dọc
  nhẹ trên sáng → dưới tối (bình thường `#3a3d44` → `#2b2e34`,
  phím đang bấm `#9aa0a8` → `#7e848d`, phím được chọn/teal `#33c0af`
  → `#25a08f`) + bóng đổ mềm (đen 33%, blur 3, lệch xuống 2px).
- Phím đang bấm thì mất bóng (cảm giác nhấn xuống).
- Tông màu trung bình mỗi trạng thái giữ nguyên như trước; bo góc 8
  và viền giữ nguyên.
- Test highlight/báo trạng thái phím cập nhật theo: helper đọc màu
  đầu gradient thay vì màu phẳng cũ.

## Kiểm chứng

- Local: `flutter analyze` 0 issue, `flutter test` pass (test mới:
  phím A có gradient + bóng đổ; 2 test highlight cũ cập nhật sang
  đọc gradient).
- Kiểm chứng thật trên máy (An): mở màn hình ra, nối RDP → phím có
  độ bóng + bóng đổ như phím laptop thật, bấm xuống thấy phím lún.

## Phiên bản

- 1.5.11+28, commit VM + PC (xem git log), CI run #27.
- Lưu ý: push cùng lúc với bước 42 (1.5.10) sau khi run #26 xong —
  một lần push, một run #27 build bản 1.5.11 gồm cả hai bước.
