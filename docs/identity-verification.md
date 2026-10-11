# OCR và đối chiếu khuôn mặt

Tính năng đọc văn bản trên ảnh giấy tờ bằng AWS Textract và đối chiếu ảnh selfie với khuôn mặt trên giấy tờ bằng AWS Rekognition. Ở màn hình **Review & submit**, người dùng chọn **Run identity checks** để gửi hai ảnh đã tải lên sang AWS. Kết quả xuất hiện trong hồ sơ của người dùng, màn hình duyệt và lịch sử từng lần nộp. Người dùng có thể sửa thông tin qua **Edit**; OCR không tự ghi đè dữ liệu đã nhập.

## Bật tính năng

Backend cần Node 22.12 trở lên, AWS credentials và region có cả hai dịch vụ. Cấu hình credentials ở backend bằng IAM role, AWS profile hoặc biến môi trường chuẩn của AWS SDK; không đưa khóa vào Flutter, Git hay tham số build của ứng dụng.

Trong `backend/.env`, đặt:

```dotenv
KYC_VERIFICATION_PROVIDER=aws
AWS_REGION=ap-southeast-1
KYC_FACE_MATCH_THRESHOLD=90
KYC_VERIFICATION_TIMEOUT_MS=7000
# Nếu dùng profile AWS ở máy phát triển:
AWS_PROFILE=kyc-development
```

IAM principal cần ba quyền sau trong region đã chọn. Adapter truyền bytes trực tiếp, không cần S3, face collection hay quyền lưu khuôn mặt:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "textract:DetectDocumentText",
        "rekognition:DetectFaces",
        "rekognition:CompareFaces"
      ],
      "Resource": "*"
    }
  ]
}
```

Áp dụng migration và khởi động lại API:

```sh
cd backend
npm ci
npm run migrate
npm run build
npm start
```

Nếu API đang chạy bằng `npm run dev`, trình theo dõi sẽ tải lại source; vẫn cần chạy migration trước. Nếu API đang chạy từ `dist`, dừng tiến trình cũ sau khi build rồi khởi động tiến trình mới. Build lại Flutter để có nút kiểm tra và phần kết quả mới. Cấu hình mặc định `KYC_VERIFICATION_PROVIDER=none` hiển thị tính năng chưa được cấu hình và không gửi ảnh ra ngoài. Chỉ bật `aws` khi đã chuẩn bị tài khoản/quyền sử dụng; mỗi lần kiểm tra có thể phát sinh phí AWS.

## Kết quả và giới hạn

- OCR trả văn bản nhận dạng, confidence trung bình của các dòng và các trường gợi ý khi tìm được nhãn English rõ ràng: full name, date of birth, document/passport/ID/licence number. Nhãn tên phải nằm riêng trên một dòng hoặc có dấu hai chấm; tên có thể ghép từ given names và surname. Nhãn tên cha/mẹ/người cấp không được dùng làm tên người nộp. Ngày hỗ trợ ISO hoặc tháng viết bằng chữ English; ngày dạng số mơ hồ được để trống. Không suy đoán trường từ vị trí hay văn bản không có nhãn.
- Adapter yêu cầu đúng một khuôn mặt trong mỗi ảnh trước khi gọi CompareFaces. Kết quả gồm matched, not matched, no face, multiple faces hoặc failed; điểm similarity là thang 0–100. Ngưỡng mặc định 90 có thể cấu hình từ 1–100 và cần được đánh giá theo dữ liệu thực tế của sản phẩm. Điểm này không phải xác suất xác minh đúng danh tính.
- OCR và đối chiếu khuôn mặt là tín hiệu hỗ trợ. Hồ sơ vẫn được nộp cho người duyệt, kể cả khi không khớp hoặc dịch vụ không khả dụng. Tính năng không kiểm tra tính thật của giấy tờ và không có liveness/chống ảnh chụp lại.
- [Textract hỗ trợ sáu ngôn ngữ](https://docs.aws.amazon.com/textract/latest/dg/limits-document.html): English, French, German, Italian, Portuguese và Spanish. Tiếng Việt và đầy đủ ký tự CCCD Việt Nam chưa được hỗ trợ; để triển khai KYC cho CCCD Việt Nam cần adapter OCR phù hợp như FPT.AI. Parser trường hiện tại dùng nhãn English. [CompareFaces](https://docs.aws.amazon.com/rekognition/latest/APIReference/API_CompareFaces.html) là phép đối chiếu hai ảnh và vẫn cần người duyệt kiểm tra.

## Lưu trữ và xử lý lỗi

Backend lấy ảnh từ media riêng tư đã được xác thực chủ sở hữu, giải mã trong bộ nhớ và gửi JPEG đã loại metadata. Ảnh gửi tới provider được giới hạn kích thước 5 MB. Kết quả OCR/đối chiếu được mã hóa AES-256-GCM bằng cùng khóa bảo vệ hồ sơ; không lưu embeddings hoặc toàn bộ phản hồi AWS. Không ghi lỗi provider chứa thông tin giấy tờ vào phản hồi HTTP hay log.

Kiểm tra chỉ chạy khi người dùng chọn nút và hồ sơ đang chỉnh sửa, đã có đủ document/selfie. Kết quả hoàn tất được dùng lại cho đúng hai media IDs. Chụp lại một ảnh sẽ xóa kết quả đang làm việc; retry cùng capture ID giữ nguyên kết quả. Các lần nộp cũ giữ snapshot kết quả và ảnh ban đầu.

Cloud IO chạy ngoài transaction. Backend kiểm tra lại media IDs/trạng thái trước khi lưu, chặn nộp khi một lượt kiểm tra đang chạy và bỏ kết quả cũ nếu ảnh đã thay đổi. Lượt kiểm tra có timeout tổng thể tối đa 8 giây, retry lỗi có cooldown 30 giây và endpoint áp dụng rate limit. OCR lỗi không xóa kết quả đối chiếu đã thành công và ngược lại. IAM/quota/network/timeout đều hiển thị failed an toàn; người dùng có thể thử lại.

Migration `006_kyc_verification.sql` chỉ thêm cột nullable, nên hồ sơ/lịch sử trước đây không bị gán kết quả mới. Khi tắt provider, bằng chứng đã lưu vẫn có thể đọc lại; việc tắt chỉ ngăn lượt kiểm tra mới.
