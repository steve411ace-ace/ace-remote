# Ace Remote v1

Flutter Android · `vn.aceremote.app` · `1.0.0+1`.

Ứng dụng điều khiển PC Windows ace qua HTTP trong Tailscale. Chỉ có một project tại thư mục này. Không deploy PC, không tạo repository/commit/push, không cấu hình ký release.

```sh
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=ACE_MOCK=true
```

Mock là cờ compile-time, không lưu trong cấu hình. Chạy không có cờ (hoặc `ACE_MOCK=false`) để dùng agent thật. Mock vẫn yêu cầu đặt/mở PIN. Sau khi kết nối, bấm biểu tượng nhật ký để xem 100 lệnh gần nhất; ảnh được vẽ cục bộ, đổi màn hình và tọa độ âm đều được mô phỏng. Không có lưu lượng đến PC trong chế độ này.

Xem [HANDOFF.md](HANDOFF.md) cho hợp đồng agent, giới hạn, kiểm chứng và checklist Muse cần thực hiện trên thiết bị thật. [FILES.md](FILES.md) liệt kê file source/cấu hình.
