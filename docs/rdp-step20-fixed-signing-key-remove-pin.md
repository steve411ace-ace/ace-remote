# Bước 20 — Fixed signing key + bỏ PIN lúc mở app

## Bối cảnh
- An yêu cầu (02:20, 14/11/2026): bản mới trên App Tester phải cho bấm "Cập nhật" tại chỗ và giữ lại dữ liệu đã lưu (mật khẩu RDP, PIN, host/port). Nguyên nhân: release ký bằng `signingConfigs.debug`, mỗi runner GitHub sinh debug keystore mới → chữ ký khác nhau mỗi lần → Android bắt gỡ/cài → gỡ là mất hết dữ liệu app.
- An chốt (02:30): "Làm fixed key ngay đi em". Sau đó An hoãn (02:35): "Phần này để sau đi em" / "Anh chưa lên máy đc" — chưa tạo được keystore + chưa thêm được 4 secrets GitHub. **Vì vậy code bước 20 làm xong để sẵn trên working tree, CHƯA PUSH.** Chỉ push sau khi An xác nhận đã thêm đủ 4 secrets (workflow sẽ lỗi nếu thiếu secret).
- An yêu cầu thêm (02:31): "bỏ phần Pin lúc đầu đi em, không cần".
- Branch: `rdp-prototype`. Toolchain: Flutter 3.50.0, AGP 9.3.1, Gradle 9.5.0, compileSdk 37.

## 1. Fixed signing key (code)

### `android/app/build.gradle`
- Đọc signing config từ file `key.properties` (do workflow tạo lúc build, KHÔNG commit). Thêm biến `hasReleaseKey` (true khi `key.properties` có `storeFile`).
- `signingConfigs.release` chỉ nạp `storeFile`/`storePassword`/`keyAlias`/`keyPassword` khi có key; `buildTypes.release` dùng `signingConfigs.release` khi có key, ngược lại fallback về `signingConfigs.debug` kèm comment — để build local không có key không vỡ.
- Không đổi version, package, logic app. `.gitignore` đã có sẵn `key.properties` và `**/*.keystore` (android/.gitignore) nên không cần sửa gì thêm — đã kiểm chứng bằng `git check-ignore`.

### `.github/workflows/build-rdp.yml` và `.github/workflows/build-apk.yml`
- Thêm bước "Restore release signing key from secrets" NGAY TRƯỚC khi `flutter build apk --release` (cả 2 workflow dùng cùng một key → cùng chữ ký, cập nhật tại chỗ được cho cả 2 bản).
- Bước này: kiểm tra 4 secret đều non-empty (`test -n ...` — thiếu secret thì build FAIL rõ ràng thay vì lặng lẽ ký bằng debug key), decode `KEYSTORE_BASE64` thành `android/app/release.keystore`, ghi `android/app/key.properties` (`storePassword`, `keyPassword`, `keyAlias`, `storeFile=release.keystore`).
- Secret không in ra log: dùng `printf '%s' | base64 -d` và heredoc có quote (`<<'PROPERTIES'`); GitHub cũng tự che secret trong log.
- Hậu quả đã báo An: bản đầu tiên ký bằng fixed key vẫn khác chữ ký bản debug đang cài → An gỡ bản cũ, cài bản mới 1 lần; từ đó về sau cập nhật tại chỗ + giữ dữ liệu.

## 2. Bỏ PIN lúc mở app

### Đã gỡ (chỉ trong `lib/main.dart`)
- Màn hình khóa PIN lúc mở app (form "Đặt PIN lần đầu" / "Mở khóa phiên" + nút "Dùng vân tay"): app mở thẳng vào `Home`.
- Toàn bộ logic PIN: `unlock()` (đặt/kiểm tra PIN + vân tay), `lock()` (khóa phiên), `digest()` (salted SHA-256 của PIN), hẹn giờ tự khóa sau 5 phút không hoạt động (`idle` timer, `lastActivity`, `didChangeAppLifecycleState` nhánh khóa), các field `auth`, `pin`, `confirmPin`, `unlocked`, `hasPin`, `busy`, `securityReady`, `biometricAvailable`, `failed`, `retryAt`, tham số `now` của `AceApp` (chỉ dùng cho hẹn giờ khóa).
- Nút "Khóa phiên" trên AppBar của `Home` + tham số `onLock` (cả ở `Home` và chỗ gọi).
- Import không còn dùng: `dart:convert`, `package:crypto/crypto.dart`, `package:local_auth/local_auth.dart`, `package:local_auth_android/local_auth_android.dart`, `rdp_credentials.dart` (chỉ main.dart gỡ import; file vẫn còn cho `rdp_surface.dart`).
- Dependency không còn dùng trong `pubspec.yaml`: `local_auth`, `local_auth_android`, `crypto` (đã chạy `flutter pub get`, `pubspec.lock` cập nhật theo; `flutter_secure_storage` vẫn giữ vì mật khẩu RDP dùng nó).
- Giữ lại: `didChangeAppLifecycleState` chỉ còn bật lại `immersiveSticky` khi resume; `error` chỉ còn cho trường hợp `SharedPreferences` load lỗi (hiện màn hình lỗi đơn giản thay vì màn hình PIN).

### KHÔNG đụng tới mật khẩu RDP (đã kiểm chứng)
- File `lib/rdp_credentials.dart` giữ nguyên 100% (storage dùng chung, key `rdp_password`, file riêng `ace_rdp_credentials`, encryptedSharedPreferences=true).
- Toàn bộ logic lưu/khôi phục/quên mật khẩu RDP trong `lib/rdp_surface.dart` giữ nguyên (dùng `rdpPasswordKey`/`rdpStorageOptions` ở các dòng 113/124/147).
- Test `test/rdp_surface_test.dart` vẫn pass 7/7 (lưu sau khi connected, khôi phục, quên mật khẩu, điền lại sau ngắt).

### Test
- Xóa `test/security_test.dart` (toàn bộ test về PIN — enrollment, hash, idle lock 5 phút, PIN sai — không còn ý nghĩa).
- `test/remote_test.dart`: gỡ tham số `onLock` khỏi chỗ tạo `Home`; thêm test mới "AceApp opens straight to Home without a PIN gate" (pump `AceApp`, settle, không còn chữ "Đặt PIN lần đầu" / "Mở khóa phiên", hiện "ace — Windows").

## Kiểm chứng (VM, SDK Flutter 3.50.0)
- `flutter analyze`: **No issues found!** (lưu ý: lần analyze đầu báo 1 lỗi `return_of_invalid_type_from_closure` ở `builder: (context, child) => child` vì `child` là `Widget?` — đã sửa bằng cách bỏ hẳn `builder`, vì nó chỉ phục vụ Listener theo dõi `lastActivity` cho tự khóa).
- `flutter test`: **38/38 pass** (38 cũ − 1 test PIN đã xóa + 1 test mới mở thẳng Home).
- YAML 2 workflow parse OK (python yaml). Không còn chuỗi `ace_pin` / `local_auth` / `onLock` nào trong `lib/`, `test/`, workflow, build.gradle. `pubspec.lock` không còn `local_auth`.
- Kotlin/Gradle (signing config mới) chưa kiểm chứng được trên VM — chỉ compile được trên CI (run #9).

## Cách test trên Fold6 (sau khi push run #9)
1. **Bỏ PIN**: mở app → vào thẳng màn hình chính, không hỏi PIN; không còn nút khóa phiên trên AppBar.
2. **Mật khẩu RDP vẫn lưu**: kết nối RDP 1 lần (nhập mật khẩu) → thoát app → mở lại → ô Password đã điền sẵn; bấm "Quên mật khẩu" thì trống lại.
3. **Fixed key (chỉ sau khi An thêm đủ 4 secrets + push run #9)**: gỡ bản debug cũ, cài bản run #9 từ App Tester 1 lần cuối → các bản sau bấm "Cập nhật" tại chỗ, mật khẩu/PIN/host còn nguyên.
