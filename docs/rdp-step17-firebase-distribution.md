# Step 17 — Firebase App Distribution cho RDP prototype

An yêu cầu lúc 23:07 ngày 13/11/2026: “ghi đè lên chỗ app test luôn”.
Bản RDP phải lên App Tester thay cho v1.4. Workflow `build-rdp.yml` thêm
bước `Upload to Firebase App Distribution` ngay sau bước upload artifact APK.
Không thêm GitHub Release; giữ nguyên trigger và các bước build/upload artifact.

Cấu hình sao chép từ `build-apk.yml`:

- Action: `wzieba/firebase-distribution-github-action@v1`.
- appId: `1:443475386602:android:51276f708ef1ddcf293793`.
- serviceCredentialsFileContent: `${{ secrets.FIREBASE_SERVICE_ACCOUNT }}`.
- file: `build/app/outputs/flutter-apk/app-release.apk`.
- testers: `steve411ace@gmail.com`.
- releaseNotes: “Ace Remote RDP prototype — nối RDP thật (branch rdp-prototype). Bản RDP-only, KHÔNG phải v1.4 agent-mode.”

Giữ nguyên `permissions: contents: read`. [Khai báo action v1](https://github.com/wzieba/Firebase-Distribution-Github-Action/blob/v1/action.yml)
hỗ trợ các input trên và chạy bằng Docker trên Linux. [Entrypoint v1](https://github.com/wzieba/Firebase-Distribution-Github-Action/blob/v1/entrypoint.sh)
ghi service account từ input vào file, đặt `GOOGLE_APPLICATION_CREDENTIALS`, rồi
gọi Firebase CLI để phân phối APK. Action không dùng `GITHUB_TOKEN` để ghi repo,
nên không cần thêm quyền GitHub hay `id-token: write`.

Sau khi CI upload thành công, App Tester sẽ hiển thị bản RDP này là bản mới nhất
thay cho v1.4, đúng yêu cầu của An. Android vẫn đòi gỡ v1.4 trước khi cài vì
khác chữ ký debug; hiện chưa có fixed signing key.

Kiểm chứng trên VM: parse workflow bằng PyYAML `safe_load`, kiểm tra cú pháp
tất cả block `run` bằng `bash -n`, và `git diff --check`. Không chạy build APK
hay Gradle trên VM. CI run tiếp theo sẽ kiểm chứng build AAR/APK, upload artifact,
khả năng chạy action trên runner, quyền Firebase của service account và việc
phân phối APK tới tester với release notes đã đặt; các kiểm tra tĩnh trên VM
không xác nhận được những thao tác Firebase này.
