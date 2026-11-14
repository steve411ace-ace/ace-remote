# Bước 30 — Fixed signing key theo cách Thuốc Vui (cập nhật tại chỗ, không cần An làm tay)

## An hỏi (07:23)

> "Mà bên thuoc vui đâu cần làm này vẫn cập nhật đc đó. Em xem làm cách nào đi"

An đúng: Thuốc Vui cập nhật tại chỗ mà không cần anh chạy script keystore hay
thêm secrets tay. Bước này áp dụng đúng cách đó cho Ace Remote. An đã ủy quyền
làm trực tiếp trên PC (07:24: "em tự vào làm luôn đi").

## 1. Thuốc Vui ký như thế nào (đã đọc code thật)

- Workflow Thuốc Vui (`D:\Source\thuoc-vui\.github\workflows\build-apk.yml`,
  đọc qua SSH ngày 14/11/2026): **không có bước nào xử lý signing**, không
  dùng secret nào cho việc ký. Nó chỉ chạy `flutter build apk --release`.
- Bí mật nằm trong `android/app/build.gradle` của Thuốc Vui (đọc qua SSH):
  một **debug keystore CỐ ĐỊNH được commit trong repo dưới dạng base64**
  (`android/app/debug.keystore.base64`, 3.556 byte, commit `410c899`
  "Thuoc Vui v1.2.0 - android/app/debug.keystore.base64"). Lúc build, Gradle
  giải mã file base64 thành `debug.keystore` rồi ký bản release bằng chính
  khóa đó (mật khẩu debug chuẩn của Android, alias `androiddebugkey`).
  Vì mọi bản build dùng cùng một khóa nên cùng một chữ ký → Android cho cài
  đè → cập nhật tại chỗ được.
- Chính comment trong build.gradle Thuốc Vui giải thích: trước đây mỗi máy
  build cloud tự tạo một debug.keystore ngẫu nhiên nên chữ ký khác nhau,
  Android không cho cài đè; nay khóa lưu dạng base64 (text, đẩy qua GitHub
  được) và giải mã lại lúc build. Comment cũng ghi rõ đây là khóa DEBUG,
  không phải khóa phát hành Play Store, và repo đó đang công khai nên đừng
  dùng nó cho bản phát hành thật.

Kết luận: Thuốc Vui không cần An làm gì thêm vì **setup đã xong từ trước**
(keystore đã commit trong repo từ v1.2.0). Ace Remote đến nay vẫn ký bằng
debug key ngẫu nhiên của từng runner GitHub nên mỗi bản một chữ ký khác nhau
→ bắt gỡ/cài.

## 2. Vì sao đường keystore + 4 secrets (bước 20) không làm được mà không cần An

Code fixed key bước 20 (commit VM `16477f1`) dùng keystore release riêng +
4 GitHub Secrets (`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`,
`KEY_PASSWORD`). Để Muse tự set 4 secrets qua API, đã kiểm tra cả 2 đường
và đều bị chặn:

- `gh` CLI trên VM (v2.102.0): **không có auth** ("You are not logged into
  any GitHub hosts"). Đăng nhập `gh` cần OAuth/device flow tương tác, không
  làm được qua API, và không có token nào để dùng.
- Connector GitHub (MCP, đã kiểm tra `list-tools` ngày 14/11/2026, trạng
  thái `connected`): có các tool tạo/sửa file, push, PR, issue… nhưng
  **không có tool nào set secret** (không có `create_secret`/`set_secret`/
  `actions_secret` hay tương đương). GitHub MCP server chính thức không
  expose API secrets.

Vì vậy đường 4 secrets bắt buộc An phải bấm tay trên web GitHub — đúng thứ
An đang hỏi "sao Thuốc Vui không cần làm". Cách Thuốc Vui (mục 1) không cần
secret nào nên làm được hoàn toàn mà không cần An.

## 3. Phát hiện quan trọng: workflow ở HEAD đã chứa bước restore bằng secrets

Commit `16477f1` (bước 20) **đã là tổ tiên** của HEAD hiện tại (`786b516`,
bước 28) trên branch `rdp-prototype` của VM. Vì vậy 2 file workflow ở HEAD
đã chứa sẵn bước "Restore release signing key from secrets"
(`build-rdp.yml:126`, `build-apk.yml:53`), bắt buộc cả 4 secrets phải tồn
tại (bước này `test -n` từng secret, thiếu là build FAIL theo thiết kế).

Hệ quả: **nếu push workflow của bước 28 nguyên như vậy đi run #16 thì run
#16 sẽ FAIL** (thiếu secrets). Việc sửa workflow trước run #16 là bắt buộc
dù có làm fixed key hay không. Bước này đã sửa luôn: bỏ bước restore bằng
secrets, thay bằng cơ chế Thuốc Vui (không cần secret).

## 4. Đã làm cho Ace Remote (theo cách Thuốc Vui)

### 4.1. Keystore cố định mới

- Tạo bằng keytool trên VM (`~/workspace/jdk17/bin/keytool`, không tương
  tác): RSA 2048, validity 10000 ngày, alias `androiddebugkey`, mật khẩu
  debug chuẩn của Android (giống hệt Thuốc Vui — mật khẩu này là hằng số
  công khai của nền tảng Android, không phải mật khẩu do Muse sinh; giá trị
  nằm trong `build.gradle` như chính Thuốc Vui làm).
- Thông tin khóa (kiểm chứng bằng `keytool -list -v`): Owner
  `CN=Android Debug, O=Android, C=US`; hiệu lực 14/11/2026 → 01/04/2054;
  SHA256 fingerprint `B3:A8:D6:F4:83:FF:14:39:DA:31:55:B6:FC:FC:32:AE:FD:8C:1D:E4:FB:DD:F3:98:CC:78:64:DA:69:D9:FA:77`.
- File base64: `android/app/debug.keystore.base64`, 3.556 byte (trùng đúng
  kích thước file của Thuốc Vui). Đã kiểm chứng round-trip: giải mã base64
  ra file nhị phân có SHA256 `7b320cfa…46bd`, khớp đúng file gốc.
- File này **được commit** (`.gitignore` chỉ chặn `**/*.keystore`, không chặn
  `*.base64` — đã kiểm chứng bằng `git check-ignore`).

### 4.2. Code đã sửa (chưa commit, chưa push)

- `android/app/build.gradle`: bỏ cơ chế bước 20 (đọc `key.properties` từ
  secrets); thay bằng cơ chế Thuốc Vui (giải mã `debug.keystore.base64`
  thành `debug.keystore` lúc build, ký bản release bằng khóa debug cố định
  đó). Không còn tham chiếu nào tới `KEYSTORE`/`key.properties` trong file.
- `.github/workflows/build-rdp.yml` và `.github/workflows/build-apk.yml`:
  **xóa bước "Restore release signing key from secrets"**; thay bằng comment
  giải thích cơ chế mới. Không còn tham chiếu nào tới `KEYSTORE` trong cả
  2 workflow (đã grep kiểm chứng). YAML cả 2 file parse OK.
- `CHANGELOG.md`: thêm 1 bullet vào mục `1.5.0+16` về cập nhật tại chỗ
  (lưu ý bản này vẫn phải gỡ/cài 1 lần cuối vì đổi chữ ký).
- Doc này: `docs/rdp-step30-fixed-key-thuoc-vui.md`.

### 4.3. Sao lưu trên PC của An (đã copy qua scp, đã kiểm chứng)

- `C:\Users\steve\ace-remote-debug.keystore` (file nhị phân gốc) —
  SHA256 trên PC `7b320cfa…46bd`, khớp đúng bản gốc trên VM
  (kiểm chứng bằng `certutil -hashfile`).
- `C:\Users\steve\ace-remote-debug.keystore.base64` (bản text, giống file
  trong repo).
- **An giữ 2 file này cẩn thận, đừng xóa.** Mất keystore = phải ký key mới
  = mọi máy phải gỡ/cài lại từ đầu. Mật khẩu là mật khẩu debug chuẩn của
  Android (giống Thuốc Vui), không cần file mật khẩu riêng.
- Bản nhị phân trên VM (`/tmp`) đã xóa sau khi copy xong; không còn bản sao
  nào trên VM ngoài file `.base64` trong repo.

### 4.4. Kiểm chứng trên VM

- `flutter analyze`: **0 issue**. `flutter test`: **96/96 pass**.
- YAML 2 workflow parse OK. Không còn chuỗi `KEYSTORE`/`key.properties`/
  `Restore release` trong workflow và build.gradle.
- Chưa kiểm chứng được trên VM (cần CI): bản run #16 có ký đúng bằng khóa
  cố định không, App Tester có cho bấm "Cập nhật" không. Đường kiểm chứng
  chính là run #16 + An test trên Fold6.

## 5. Đề xuất sequencing: GỘP fixed key vào run #16

**Đề xuất: gộp vào run #16 cùng bước 28 + bước 29, không để run #17 riêng.**

Lý do:

1. Workflow ở HEAD đã chứa bước restore bằng secrets (mục 3) — run #16
   bắt buộc phải sửa workflow trước khi push, dù có gộp fixed key hay
   không. Sửa thành cơ chế Thuốc Vui hay chỉ xóa bước restore thì cũng cùng
   một lần chạm vào 2 workflow; gộp luôn thì được fixed key ngay trong run
   này, không tốn thêm một run.
2. Không xung đột file: bước 30 sửa `build.gradle`, 2 workflow, CHANGELOG,
   thêm `debug.keystore.base64` + doc. Bước 29 chỉ sửa file native widget
   (provider Kotlin + layout/drawables). Bước 28 đã xong (commit `786b516`).
   Ba bộ đổi không đụng nhau.
3. Version `1.5.0+16` đã ghi trong CHANGELOG (mục fixed key đã thêm);
   parent chỉ cần thêm bullet của bước 29 vào cùng mục này trước khi push.

Lưu ý cho parent khi push run #16: file `android/app/build.gradle` phải
được đưa vào danh sách archive sang PC (từ trước đến nay parent vẫn loại
trừ build.gradle khỏi các đợt push để tránh kèm fixed key — lần này PHẢI
kèm, vì build.gradle mới là một phần của cơ chế Thuốc Vui). Kèm cả file
mới `android/app/debug.keystore.base64`. **Không kèm** file
`C:\Users\steve\create-ace-remote-keystore.ps1` hay keystore release cũ
(nếu có) — chúng thuộc đường secrets bước 20, đã bỏ.

## 6. Đánh đổi: khóa debug cố định vs keystore release (bước 20)

- Cách Thuốc Vui dùng khóa **debug** (mật khẩu chuẩn công khai). Đủ dùng
  vì Ace Remote chỉ phát qua Firebase App Distribution cho tester, không
  phát hành Play Store — giống hệt Thuốc Vui. Rủi ro: ai có file
  `.base64` trong repo cũng ký được app giả mạo cùng chữ ký (repo này
  private nên rủi ro thấp hơn repo công khai của Thuốc Vui).
- Đường bước 20 dùng keystore **release** riêng + secrets thì "đúng chuẩn"
  hơn, nhưng không tự động được (mục 2) và vẫn cần An bấm tay — đúng thứ
  An vừa hỏi sao Thuốc Vui không cần làm.
- Nếu sau này An muốn chuyển sang keystore release riêng thì vẫn làm được
  (tạo keystore mới + 4 secrets + quay lại cơ chế bước 20), nhưng sẽ lại
  phải gỡ/cài 1 lần cuối vì đổi chữ ký. Hiện tại, cách Thuốc Vui là lựa
  chọn đúng với yêu cầu của An.

## 7. An còn phải làm gì

**Không còn việc gì cho phần ký.** An không cần chạy script keystore, không
cần thêm secrets GitHub nữa (hướng dẫn cũ lúc 02:33 và 07:20–07:23 coi như
hủy — script `C:\Users\steve\create-ace-remote-keystore.ps1` trên PC không
cần dùng nữa).

Việc duy nhất còn lại là **test**: khi run #16 lên App Tester, An gỡ bản cũ
cài bản 1.5.0 (16) **1 lần cuối** (vì đổi chữ ký), rồi từ bản sau trở đi cứ
bấm "Cập nhật" tại chỗ, không mất kết nối đã lưu.
