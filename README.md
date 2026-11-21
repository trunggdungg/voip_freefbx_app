# EAUT VoIP (voip_freefbx_app)

App Android gọi VoIP cho tư vấn tuyển sinh: đăng nhập bằng tài khoản Odoo, lấy cấu hình SIP
từ Odoo (module `voip_webrtc_freepbx`) và đăng ký extension qua WSS tới FreePBX.

Tiến độ: **M0** khung dự án ✔ · **M1** đăng nhập Odoo + lấy cấu hình SIP ✔ · **M2** đăng ký SIP qua WSS ✔ · **M3** gọi đi ✔ · M4 nhận cuộc gọi (tiếp theo).

## Gọi đi (M3)
Nút **Bàn phím** ở trang chính mở bàn phím số (giữ phím `0` để nhập `+`; mã tính năng như `*43` gọi được).
Chỉ gọi được khi đã **Đăng ký**. Màn hình cuộc gọi có: tắt tiếng, loa ngoài, giữ máy, bàn phím DTMF,
kết thúc; hiện thời lượng và lý do khi thất bại (máy bận, sai số, bị từ chối...). Cần quyền micro.
Chưa xử lý cuộc gọi đến (M4): có người gọi vào thì app chưa đổ chuông.

## Đăng ký SIP (M2)
Sau khi lấy cấu hình, app mở WebSocket tới FreePBX và đăng ký `sip:<extension>@<realm>` giống
softphone web. Trạng thái hiển thị trên trang chính (Đang kết nối / Đã đăng ký / Mất kết nối / Lỗi).
Đăng xuất thì hủy đăng ký. **Một extension chỉ nên đăng ký ở một nơi**: khi test, đóng web softphone
của cùng user.

## Đăng nhập (M1)
App dùng endpoint sẵn có của Odoo: `POST /web/session/authenticate` (cookie `session_id`) và
`POST /voip/config`. Chỉ lưu địa chỉ, database, tên đăng nhập và session trong secure storage;
**mật khẩu Odoo và mật khẩu SIP không được lưu**, cấu hình SIP chỉ nằm trong bộ nhớ.

Địa chỉ Odoo khi test: máy ảo Android dùng `http://10.0.2.2:8069`, điện thoại thật dùng IP LAN.

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
