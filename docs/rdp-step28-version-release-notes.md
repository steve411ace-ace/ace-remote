# Bước 28 — Phiên bản và release notes như Thuốc Vui

An (07:11, 14/11/2026): "Bản nào em cũng để 1.4 (5) hết em. Rồi releasenote
chung chung nữa. Em ghi phiên bản với release note chi tiết như thuoc vui
vậy đó."

## 1. Thuốc Vui làm thế nào (đã đọc code thật)

### Phiên bản: bump tay trong `pubspec.yaml`, mỗi bản một lần

- Bằng chứng 1 — git log của Thuốc Vui trên PC (`D:\Source\thuoc-vui`,
  `git log --oneline -- pubspec.yaml`):
  `7ab8883 Thuoc Vui v1.2.37: ...`, `cc52e48 Thuoc Vui v1.2.36: ...`,
  `6975d17 Thuoc Vui v1.2.35: ...` — mỗi bản là MỘT commit vừa bump
  `version:` (cả versionName và build number: 1.2.35+38 → 1.2.36+39 →
  1.2.37+40) vừa mô tả thay đổi trong tiêu đề commit.
- Bằng chứng 2 — `D:\Source\thuoc-vui\.github\workflows\build-apk.yml`
  (đọc trực tiếp qua SSH ngày 14/11/2026): workflow KHÔNG có bước nào tăng
  version — version lấy nguyên từ `pubspec.yaml`. Skill chuẩn Thuốc Vui
  (mục 3.4) cũng ghi: "Mỗi bản tăng cả version và build number
  (kiểu `1.2.15+18`), và hiển thị đúng số phiên bản đó trong Settings."
- Không có file CHANGELOG.md trong repo Thuốc Vui.

### Release notes: Thuốc Vui KHÔNG tự sinh trong CI

- Workflow Thuốc Vui ở bước "Upload to Firebase App Distribution"
  (`wzieba/firebase-distribution-github-action@v1`) KHÔNG truyền
  `releaseNotes` hay `releaseNotesFile` (đã đọc file thật). Nghĩa là trên
  App Tester, bản Thuốc Vui không có release notes nào từ CI.
- Release notes chi tiết mà An thấy ở Thuốc Vui thực ra là:
  (a) tiêu đề commit của từng bản ("Thuoc Vui v1.2.37: ..."), và
  (b) bản tóm tắt chi tiết Muse viết trong chat mỗi khi giao bản.
- Bước GitHub release của Thuốc Vui cũng ghi cứng `tag_name: v1.0.0`
  (không bao giờ đổi) và không có `body`.

### Kết luận: Ace Remote làm theo Thuốc Vui, và hơn một bậc ở release notes

- **Phiên bản: giống hệt Thuốc Vui** — bump tay `version:` trong
  `pubspec.yaml` mỗi bản (cả versionName và build number). Không tự tăng
  trong CI, vì đó không phải cách Thuốc Vui làm.
- **Release notes: hơn Thuốc Vui** — thay vì để trống như Thuốc Vui, Ace
  Remote giữ một `CHANGELOG.md` (mục mới nhất = nội dung của bản đó) và CI
  tự lấy mục mới nhất làm release notes trên App Tester. Nguồn nội dung vẫn
  là "mô tả của từng bản" như Thuốc Vui (commit message), chỉ khác là được
  ghi có cấu trúc trong CHANGELOG thay vì chỉ nằm trong tiêu đề commit.
- **Chống quên: CI chặn build nếu quên tăng version.** Đây là phần Thuốc
  Vui không có — và chính là lỗi đã làm 11 bản RDP (runs #5–#15) đều là
  1.4.0 (5): không ai nhớ bump. Từ giờ, quên bump thì build lỗi ngay ở
  bước đầu (trước cả bước build AAR tốn 3 phút), không còn bản trùng
  version lọt ra App Tester nữa.

## 2. Cách Ace Remote làm (bước 28)

### Quy tắc bump version (cho mọi bước sau này)

1. Mỗi bước/release: tăng `version:` trong `pubspec.yaml`.
   - versionName tăng theo mức thay đổi: sửa lỗi nhỏ → tăng patch
     (1.5.0 → 1.5.1); thêm tính năng → tăng minor (1.5.0 → 1.6.0);
     thay đổi lớn/không tương thích → tăng major.
   - Build number tăng ít nhất +1 và KHÔNG BAO GIỜ giảm (Android bắt buộc
     versionCode tăng đơn điệu, nếu không sẽ không cập nhật được).
   - Nên để build number bằng số run CI sắp tới để dễ đối chiếu
     (ví dụ bản run #16 → build number 16).
2. Thêm một mục mới ở ĐẦU `CHANGELOG.md`, tiêu đề đúng dạng
   `## [<versionName>+<buildNumber>] - YYYY-MM-DD`, nội dung là danh sách
   gạch đầu dòng những gì thay đổi trong bản đó.
3. Cài đặt của app hiện số phiên bản đang cài (ví dụ "Phiên bản 1.5.0 (16)")
   để An kiểm tra đúng bản đã cài hay chưa.

### Các file mới / đổi

| File | Đổi gì |
| --- | --- |
| `pubspec.yaml` | `version: 1.4.0+5` → `1.5.0+16`; thêm `package_info_plus: ^8.0.0` (đọc version thật từ APK để hiện trong Cài đặt) |
| `pubspec.lock` | Sinh lại bằng `flutter pub get` (thêm package_info_plus) |
| `CHANGELOG.md` | Mới. Mục `1.5.0+16` (bước 28) + mục `1.4.0+5` tóm tắt runs #5–#15 làm mốc |
| `scripts/check_version.py` | Mới. Cổng kiểm tra version: so `pubspec.yaml` hiện tại với commit trước (`HEAD~1`); lỗi khi version không đổi hoặc build number không tăng |
| `scripts/release_notes.py` | Mới. Lấy mục mới nhất của CHANGELOG.md làm release notes (thêm dòng đầu `Ace Remote <versionName> (<buildNumber>)`); fallback sang commit message khi CHANGELOG thiếu/lệch version |
| `.github/workflows/build-rdp.yml` | checkout `fetch-depth: 2`; thêm bước "Check version was bumped" ngay sau checkout (lỗi sớm, trước bước build AAR); thêm bước "Generate release notes from CHANGELOG"; bước Firebase đổi `releaseNotes:` (dòng chung chung cũ) thành `releaseNotesFile: release-notes.txt`. **Bước "Restore release signing key from secrets" KHÔNG đổi.** |
| `.github/workflows/build-apk.yml` | Như trên, cộng: bước "Read version from pubspec" (xuất `version_name`/`build_number`); bước GitHub release đổi tag ghi cứng `v1.4.0` thành `v<versionName>` động, `name` kèm build number, `body_path: release-notes.txt`; bước Firebase thêm `releaseNotesFile`. **Bước fixed key KHÔNG đổi.** |
| `lib/main.dart` | Cài đặt hiện "Phiên bản X (Y)" ở cuối trang (đọc bằng `package_info_plus`, có try/catch nên không vỡ khi plugin thiếu) |
| `test/settings_test.dart` | Thêm test: mock `PackageInfo` 1.5.0/16 thì Cài đặt hiện "Phiên bản 1.5.0 (16)" |

### Luồng trên CI (run #16 trở đi)

1. Checkout (`fetch-depth: 2`) → "Check version was bumped" chạy
   `scripts/check_version.py`: so version hiện tại với commit trước.
   Không tăng → build FAIL ngay, log ghi rõ phải bump `pubspec.yaml`.
2. Build AAR/APK như cũ (đọc version từ `pubspec.yaml` qua
   `flutter.versionName`/`flutter.versionCode` trong `build.gradle`).
3. "Generate release notes from CHANGELOG" chạy
   `scripts/release_notes.py` → ghi `release-notes.txt`, in ra log.
4. Upload Firebase với `releaseNotesFile: release-notes.txt` → App Tester
   hiện version mới + release notes chi tiết của bản đó.

## 3. Bản run #16 sẽ là gì (dự kiến)

- **Version: 1.5.0 (16)** — versionName 1.5.0 (tăng minor: từ 1.4.0 đã có
  RDP rewrite + widget + nhiều tính năng), build number 16 (bằng số run
  #16, và > 5 nên Android cập nhật được).
- **Release notes trên App Tester** (sinh từ CHANGELOG, đã chạy thử trên VM):

```text
Ace Remote 1.5.0 (16)

- Phiên bản tăng lên 1.5.0 (16): sửa cách đánh phiên bản — mỗi bản build giờ
  có số phiên bản mới, không còn 1.4.0 (5) mãi như 11 bản trước (runs #5–#15).
- Release notes chi tiết: mỗi bản lên App Tester kèm danh sách thay đổi lấy
  từ mục mới nhất của CHANGELOG này (trước đây chỉ có một dòng chung chung).
- CI kiểm tra: build sẽ lỗi nếu quên tăng version trong `pubspec.yaml`
  (so với commit trước) hoặc build number không tăng.
- Cài đặt hiện số phiên bản của app đang cài (ví dụ "Phiên bản 1.5.0 (16)"),
  để kiểm tra đúng bản đã cài hay chưa.
```

## 4. Kiểm chứng

- Đã chạy trên VM:
  - `scripts/check_version.py` với pubspec 1.4.0+5 so với HEAD~1 (cũng
    1.4.0+5) → FAIL đúng như mong đợi (bắt đúng lỗi 11 bản trước); với
    1.5.0+16 → PASS; với build number giảm (17 → 16) → FAIL.
  - `scripts/release_notes.py` với CHANGELOG thật → ra đúng 10 dòng như
    mục 3; với CHANGELOG lệch version → cảnh báo + fallback sang commit
    message (18 dòng, vẫn có nội dung).
  - YAML cả 2 workflow parse OK bằng PyYAML (16 bước build-rdp.yml,
    13 bước build-apk.yml); diff xác nhận bước fixed key không đổi.
  - `flutter analyze`: 0 issue. `flutter test`: 96/96 pass (95 cũ + 1 mới).
- Chưa kiểm chứng được trên VM (cần run #16): version 1.5.0 (16) có hiện
  đúng trên App Tester không, release notes chi tiết có hiện không, và
  bước "Check version was bumped" có chạy đúng trên runner không
  (đặc biệt `fetch-depth: 2` và `git show HEAD~1`).

## 5. Cách kiểm chứng trên run #16 (cho An)

1. Sau khi run #16 SUCCESS, mở App Tester: bản mới phải hiện
   **1.5.0 (16)** (không còn 1.4.0 (5)), kèm release notes 4 gạch đầu
   dòng như mục 3.
2. Gỡ bản cũ, cài bản 1.5.0 (16), mở Cài đặt: cuối trang phải hiện
   **"Phiên bản 1.5.0 (16)"**.
3. Kiểm tra log run #16: bước "Check version was bumped" in ra
   `previous 1.4.0+5 -> current 1.5.0+16` và `OK`; bước "Generate
   release notes from CHANGELOG" in ra đúng 10 dòng notes.

> Lưu ý: run #16 còn gộp cả **bước 29** (sửa widget theo phản hồi của An
> trên bản run #15: nút bấm đổi trạng thái ngay trên widget không mở app,
> bỏ nút "Kết nối", làm đẹp widget). Trước khi push run #16, phải thêm
> các thay đổi của bước 29 vào mục `1.5.0+16` của CHANGELOG.md để release
> notes nhắc tới cả hai bước — mục hiện tại mới chỉ ghi bước 28.
