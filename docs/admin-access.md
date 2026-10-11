# Admin, reviewer và yêu cầu cấp quyền

| Quyền         | Chức năng                                                                        |
| ------------- | -------------------------------------------------------------------------------- |
| `user`        | Làm hồ sơ của mình; gửi yêu cầu xin quyền reviewer                               |
| `reviewer`    | Duyệt hồ sơ đang chờ của người khác; xem thông tin và ảnh phục vụ việc duyệt     |
| `super_admin` | Tạo tài khoản, cấp/thu hồi reviewer, quyết định yêu cầu cấp quyền và duyệt hồ sơ |

Đăng ký công khai luôn tạo `user`. Chỉ có một `super_admin`; API quản lý không cho tạo thêm hoặc hạ quyền tài khoản này. Reviewer và admin không thể duyệt hồ sơ của chính mình.

## Khởi tạo admin đầu tiên

Sau khi PostgreSQL chạy:

```sh
cd /Users/vinhngo/KYC-Onboarding-App
nvm use
cd backend
npm run migrate
npm run admin:bootstrap
```

Email local mặc định là `admin@kyc.com`. Lệnh sinh mật khẩu ngẫu nhiên mạnh, lưu email/mật khẩu vào **`backend/.local/super-admin.json`**, với quyền file `600` và được Git ignore. Mật khẩu không in ra terminal và không nằm trong source code. Mở file này trên máy để lấy thông tin đăng nhập; giữ riêng và không đưa vào commit/screenshot. Admin khởi tạo đã xác minh email và có thể đăng nhập ngay.

Tài khoản admin trong database local hiện tại đã được đổi email thành `admin@kyc.com` và giữ mật khẩu riêng theo yêu cầu để kiểm thử; thông tin hiện tại được cập nhật trong file credentials trên. Phiên đăng nhập admin trước khi đổi email đã được thu hồi: đăng nhập lại bằng email mới. Lệnh bootstrap cho database mới vẫn sinh mật khẩu mạnh, và chạy lại không đặt lại mật khẩu của admin đã có.

Có thể chọn email khi khởi tạo lần đầu:

```sh
npm run admin:bootstrap -- --email owner@kyc.example
```

Chạy lại với cùng email giữ nguyên admin và mật khẩu. Nếu email đã thuộc tài khoản thường, bootstrap từ chối thay vì tự nâng quyền. Nếu đã có admin với email khác, lệnh từ chối. Nếu reset database nhưng còn file credentials cũ, cất file cũ riêng hoặc xóa sau khi xác nhận không cần nữa trước khi bootstrap; lệnh không ghi đè file.

Trong production, operator phải cung cấp `BOOTSTRAP_ADMIN_EMAIL` và `BOOTSTRAP_ADMIN_PASSWORD` qua secrets của môi trường, dùng email nhận thư thực tế. Lệnh không dùng thông tin local mặc định và không ghi file credentials production. Bootstrap là thao tác vận hành có quyền database, không phải endpoint công khai.

## Tạo tài khoản và cấp quyền trong app

Home của `super_admin` chỉ hiển thị thông tin tài khoản, **Manage accounts**, **Review profiles** và đăng xuất. Admin không có phần verification status hoặc các bước nộp hồ sơ cá nhân; đường dẫn `/kyc/*` chuyển về Home admin. Home của user/reviewer vẫn hiển thị luồng KYC của chính mình.

1. Đăng nhập admin, từ Home mở **Manage accounts**.
2. Tạo tài khoản bằng email, mật khẩu ban đầu và quyền `user` hoặc `reviewer`. Người dùng đăng nhập rồi xác minh OTP; local đọc thư trong [Mailpit](http://127.0.0.1:8025). Mật khẩu tối thiểu 12 ký tự, có chữ hoa, chữ thường và số.
3. Trong danh sách tài khoản, cấp reviewer hoặc thu hồi về user.
4. Người dùng tự đăng ký mở **Account access**, nhập lý do 10–1000 ký tự và gửi yêu cầu reviewer. Mỗi người chỉ có một yêu cầu đang chờ.
5. Admin xử lý yêu cầu trong **Manage accounts**, chấp thuận hoặc từ chối kèm lý do. Chấp thuận cấp reviewer; từ chối giữ quyền hiện tại. Sau khi bị từ chối/thu hồi, người dùng có thể gửi yêu cầu mới.
6. Người dùng chọn **Refresh** để cập nhật quyền và nút điều hướng trên app.

Các danh sách có phân trang. Quyền được đọc từ database ở mỗi request, không lấy quyền cũ từ JWT. Khi bị thu hồi, access token hiện có cũng mất quyền reviewer. App xóa thông tin/ảnh reviewer đang giữ khi nhận lỗi quyền và cho cập nhật lại quyền tài khoản.

## Duyệt hồ sơ

Đăng nhập reviewer/admin, mở **Review profiles** từ Home. Chọn hồ sơ chờ, xem chi tiết, ảnh giấy tờ và selfie, rồi duyệt hoặc từ chối. Từ chối cần lý do 3–1000 ký tự và ít nhất một bước làm lại: thông tin cá nhân, giấy tờ hoặc selfie. Chỉ hồ sơ `pending_review` được duyệt; quyết định đồng thời chỉ lưu một kết quả.

Danh sách có bộ lọc **Pending review** (chưa duyệt, mặc định), **Approved** (đã duyệt), **Rejected** (bị từ chối) và **All**. Nhập email hoặc một phần email vào **Search by email** để tìm, không phân biệt chữ hoa/thường; nút xóa trong ô tìm kiếm bỏ từ khóa. Bộ lọc và tìm kiếm kết hợp với nhau trên toàn bộ kết quả trước khi phân trang. Đổi bộ lọc hoặc từ khóa quay về trang đầu; tải lại và chuyển trang giữ điều kiện hiện tại. Hồ sơ đã duyệt/bị từ chối mở lịch sử ở chế độ chỉ đọc; quay lại giữ bộ lọc và từ khóa. Các trạng thái là trạng thái hiện tại của hồ sơ, không bao gồm hồ sơ chưa nộp hoặc đang chỉnh sửa để nộp lại.

Người nộp hồ sơ mở màn hình kết quả và **Refresh status**. Nếu bị từ chối, **Update and resubmit** mở lại bước được yêu cầu, giữ phần đã chấp nhận. Ảnh vẫn yêu cầu xác thực, không có URL media công khai.

Trạng thái KYC có màu nhất quán trên Home, màn hình kết quả và phần xem hồ sơ: **Not started** xám, **In progress** xanh dương, **Pending review** vàng nâu, **Verified** xanh lá, **Rejected** đỏ. Mỗi trạng thái có nhãn và biểu tượng, nền nhạt và viền; màu chữ đạt tương phản ít nhất 4.5:1.

`npm run review` cũ đã ngừng ghi trực tiếp database và hướng dẫn dùng app. Duyệt là thủ công; chưa có OCR, so khớp khuôn mặt hoặc liveness.

## API và lịch sử

- `GET/POST /api/v1/access/role-request`: yêu cầu mới nhất của chính mình / tạo yêu cầu.
- `GET/POST /api/v1/admin/users`: danh sách / tạo tài khoản.
- `PUT /api/v1/admin/users/:userId/role`: cấp/thu hồi reviewer.
- `GET /api/v1/admin/role-requests`: danh sách yêu cầu; hỗ trợ `status`, `limit`, `offset`, mặc định đang chờ.
- `POST /api/v1/admin/role-requests/:id/decision`: chấp thuận/từ chối.
- `GET /api/v1/reviews`: danh sách hồ sơ của người khác; hỗ trợ `status=pending_review|verified|rejected|all`, `search` theo email (tối đa 254 ký tự), `limit` và `offset`. Mặc định đang chờ duyệt.
- `GET /api/v1/reviews/:userId`: chi tiết hồ sơ chờ và `submissionId` của lần nộp đang xem.
- `GET /api/v1/reviews/:userId/media/:kind?submissionId=<uuid>`: ảnh JPEG riêng tư của đúng lần nộp đó.
- `POST /api/v1/reviews/:userId/decision`: quyết định KYC; body bắt buộc có `submissionId` lấy từ chi tiết.

Khi app trở lại từ background, app kiểm tra phiên/quyền và tải lại màn hình hiện tại. Nút quản lý/duyệt bị khóa cho tới khi dữ liệu được xác nhận; bản nháp lý do vẫn được giữ nếu lần nộp không đổi. Nếu có lần nộp mới, ảnh hoặc quyết định dùng ID cũ nhận `409 KYC_REVIEW_CHANGED` và phải tải lại trước khi duyệt. Cập nhật backend và mobile cùng lúc; client cũ thiếu `submissionId` nhận lỗi validation400.

Migration `004_account_roles.sql` giữ tài khoản hiện có là `user`, thêm `role_requests` và `role_audit_events`. Lịch sử thay đổi quyền lưu người thực hiện, tài khoản đích, quyền cũ/mới và thời điểm. Yêu cầu lưu người quyết định; `kyc_reviews` mới lưu `reviewed_by` và lý do từ chối. Quyết định CLI trước migration giữ `NULL` ở trường người duyệt.

Phân quyền này bảo vệ API và app. Người giữ credentials database có quyền ghi hoặc toàn quyền máy/backend vẫn có thể sửa database trực tiếp; muốn giới hạn công cụ/AI cần tách môi trường và quyền database như đã trao đổi.
