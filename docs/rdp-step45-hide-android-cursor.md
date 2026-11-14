# Bước 45 — Ẩn con trỏ Android trên màn hình remote

## Yêu cầu (An, 14/11 22:06, mục 2 trong 4 cải tiến)

Cắm chuột rời vào thì Android vẽ mũi tên hệ thống chồng lên con trỏ
PC — 2 con trỏ cùng lúc, nhìn rối.

## Thay đổi (chỉ native, không đổi Dart)

- `RdpPlugin.kt` (`RdpView.init`): đặt `surface.pointerIcon =
  PointerIcon.getSystemIcon(context, PointerIcon.TYPE_NULL)` cho
  SurfaceView của màn hình remote.
- Vì con trỏ hệ thống chỉ xuất hiện khi có thiết bị trỏ (chuột)
  nên TYPE_NULL không ảnh hưởng gì tới dùng cảm ứng. Vùng bàn phím
  (Flutter) vẫn giữ mũi tên Android, vì ở đó không có con trỏ PC
  nào vẽ thay.
- API 24+, minSdk 29 — không cần kiểm tra version.

## Kiểm chứng

- Local: `flutter analyze` 0 issue, `flutter test` pass (không có
  thay đổi Dart). Phần native do CI biên dịch (VM không build được
  APK).
- Kiểm chứng thật trên máy (An): cắm chuột Bluetooth vào Fold6, nối
  RDP, di chuột trên màn hình remote → chỉ thấy 1 con trỏ (của PC),
  không còn mũi tên Android chồng lên; chạm cảm ứng vẫn bình thường.

## Phiên bản

- 1.5.13+30, commit VM + PC (xem git log), CI run #29.
