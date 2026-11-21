# EAUT VoIP (voip_freefbx_app)

App Android gọi VoIP cho tư vấn tuyển sinh: đăng nhập bằng tài khoản Odoo, lấy cấu hình SIP
từ Odoo (module `voip_webrtc_freepbx`) và đăng ký extension qua WSS tới FreePBX.

Tiến độ: **M0 – khung dự án** (xem kế hoạch M0 → M5 trong phiên làm việc).

## Yêu cầu
- Flutter 3.38.x (Dart 3.10), Android SDK, JDK 17
- Điện thoại Android thật (API 24+), cùng mạng với Odoo/FreePBX khi test

## Chạy thử

Sửa `config/dev.json` cho đúng Odoo của bạn (`ODOO_URL` phải truy cập được từ điện thoại,
không dùng `localhost`), rồi:

```bash
flutter pub get
```

```bash
flutter run --dart-define-from-file=config/dev.json
```

Bản prod (cần HTTPS hợp lệ):

```bash
flutter build apk --release --dart-define-from-file=config/prod.json
```

Kiểm tra mã nguồn:

```bash
flutter analyze && flutter test
```

## Môi trường
| Khóa | Ý nghĩa |
|---|---|
| `APP_ENV` | `dev` hoặc `prod` |
| `ODOO_URL`, `ODOO_DB` | Giá trị gợi ý sẵn ở màn hình đăng nhập |
| `ALLOW_BAD_CERT` | Chấp nhận chứng chỉ tự ký, **chỉ có hiệu lực khi `APP_ENV=dev`** |

Các file `config/*.json` không chứa secret. Mật khẩu/token chỉ lưu trong secure storage sau khi đăng nhập.

## Cấu trúc
```
lib/
  core/        config, router, permissions (dùng chung)
  features/    mỗi tính năng một thư mục (home, sau này auth, sip, call, history)
```

## Android
- `applicationId`: `com.eaut.voipcrm`, `minSdk` 24 (yêu cầu của flutter_webrtc)
- Bản debug cho phép `http://` (LAN); bản release bắt buộc HTTPS
- Quyền khai báo: micro, thông báo, âm thanh/Bluetooth, mạng
