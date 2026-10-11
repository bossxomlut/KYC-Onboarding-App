# OCR và đối chiếu khuôn mặt

Ứng dụng có hai chế độ kiểm tra thật: **local** dùng Tesseract và OpenCV ngay trên server của app; **aws** dùng Textract và Rekognition. User chỉ nhập thông tin, tải ảnh và chọn **Submit for verification**. Nếu provider đã bật và hai ảnh chưa có kết quả hoàn tất phù hợp, app chạy kiểm tra trước khi nộp. Kết quả chỉ hiển thị cho **reviewer** ở màn hình duyệt và lịch sử hồ sơ reviewer; User không thấy bảng kết quả, tên provider hay nút chạy riêng. OCR không ghi đè thông tin đã nhập; KYC vẫn do người duyệt quyết định.

Selfie có **hai kết quả riêng**:

1. **Selfie face check:** phát hiện một khuôn mặt người, không có khuôn mặt, nhiều khuôn mặt hoặc không kiểm tra được. Đây là phát hiện khuôn mặt trong ảnh, chưa xác nhận người đang hiện diện trực tiếp.
2. **Face comparison:** đối chiếu khuôn mặt selfie với khuôn mặt trên giấy tờ. Chỉ đối chiếu khi mỗi ảnh có đúng một khuôn mặt. Nếu selfie có khuôn mặt nhưng giấy tờ thiếu khuôn mặt hoặc đối chiếu bị lỗi, kết quả phát hiện selfie vẫn được giữ.

## Chạy miễn phí với local

Chế độ local không cần tài khoản cloud, API key hay phí theo lượt. Ảnh không gửi sang dịch vụ nhận dạng bên ngoài. Engine dùng CPU của server; khi server nằm trên Mac phát triển, toàn bộ OCR/đối chiếu chạy trên Mac, không chạy trên điện thoại. Chi phí thuê server vẫn có nếu triển khai lên máy chủ trả phí.

Cài **Python 3.11+** và Tesseract. Trên macOS:

```sh
brew install tesseract
```

Trên Debian/Ubuntu, cài `python3`, `python3-venv` và `tesseract-ocr` bằng package manager. Từ thư mục gốc repo, chạy:

```sh
python3 scripts/setup-local-verification.py
```

Script tạo Python venv riêng trong `backend/.local/identity-venv`, cài các package đã pin trong `backend/local-verification/requirements.txt`, tải YuNet/SFace cùng dữ liệu ngôn ngữ `vie`/`eng` và xác nhận SHA-256 trước khi cài. File hỏng hoặc tải chưa xong không thay thế file cũ. Tổng model/ngôn ngữ khoảng 44 MB, không đưa vào Git. Cần mạng khi cài lần đầu; kiểm tra ảnh sau đó không gọi mạng. Giấy phép và nguồn tải ở [third-party notes](../backend/local-verification/THIRD_PARTY.md).

Trong `backend/.env`, đặt:

```dotenv
KYC_VERIFICATION_PROVIDER=local
KYC_FACE_MATCH_THRESHOLD=36.3
KYC_VERIFICATION_TIMEOUT_MS=7000
# Mặc định OCR tiếng Việt; có thể chọn eng, vie+eng hoặc eng+vie:
KYC_LOCAL_OCR_LANGUAGES=vie
```

Không ghi đè `.env` hoặc đổi các khóa mã hóa cũ. Hai đường dẫn có mặc định tương đối với thư mục `backend`:

```dotenv
# KYC_LOCAL_PYTHON=/absolute/path/backend/.local/identity-venv/bin/python
# KYC_LOCAL_MODELS_DIR=/absolute/path/backend/.local/identity-models
# TESSERACT_CMD=/absolute/path/to/tesseract
```

Chạy backend từ thư mục `backend`. Nếu `.env` cũ có `KYC_FACE_MATCH_THRESHOLD=90` của AWS, đổi sang `36.3` hoặc xóa dòng để chọn mặc định theo provider. Hai engine có thang điểm khác nhau; không dùng ngưỡng AWS cho local.

Kiểm tra lại cài đặt mà không tải/cài thêm:

```sh
python3 scripts/setup-local-verification.py --check
```

Sau khi thay `.env`, **khởi động lại API** để nạp cấu hình. Với lần cài mới, áp dụng migration trước:

```sh
cd backend
npm ci
npm run migrate
npm run dev
```

Nếu API đang chạy, dừng phiên API đó rồi chạy lại `npm run dev`. Nếu dùng bản biên dịch, chạy `npm run build` rồi `npm start`. Khi mã Flutter thay đổi, build/chạy lại app theo [local setup](local-setup.md). Tại Review phía User chỉ có hành động nộp hồ sơ. Kiểm tra chỉ chạy theo lần bấm Submit khi đã có đủ ảnh được tải lên; không tự chạy khi mở trang hoặc đọc lịch sử.

## Bật AWS khi có tài khoản

Backend cần credentials AWS và region có cả hai dịch vụ. Dùng IAM role, AWS profile hoặc biến môi trường chuẩn của AWS SDK ở backend; không đưa khóa vào Flutter hay Git.

```dotenv
KYC_VERIFICATION_PROVIDER=aws
AWS_REGION=ap-southeast-1
KYC_FACE_MATCH_THRESHOLD=90
KYC_VERIFICATION_TIMEOUT_MS=7000
# AWS_PROFILE=kyc-development
```

IAM principal cần các quyền `textract:DetectDocumentText`, `rekognition:DetectFaces` và `rekognition:CompareFaces` trên resource `*`. Adapter truyền bytes trực tiếp, không cần S3 hay face collection. Khởi động lại API sau khi đổi cấu hình. AWS tính phí hoặc trừ credits theo lượt sử dụng; chưa có credentials thì không chạy kiểm tra AWS thật.

`KYC_VERIFICATION_PROVIDER=none` tắt các kiểm tra mới. Đây là mặc định an toàn cho cài đặt chưa chuẩn bị engine. Bằng chứng đã lưu vẫn đọc được khi tắt provider.

## Kết quả dành cho reviewer

Bảng **Identity checks** dùng dữ liệu thật đã trả về và lưu với hồ sơ:

- OCR: trạng thái, tên, ngày sinh, số giấy tờ và confidence khi có.
- Selfie: phát hiện khuôn mặt, không có, nhiều khuôn mặt hoặc lỗi.
- Face match: khớp/không khớp, điểm tương đồng và ngưỡng khi có.
- Thời điểm kiểm tra; **OCR text** chỉ mở khi reviewer cần đọc toàn bộ văn bản.

Trường chưa được trích xuất hiển thị **—**; bằng chứng chưa chạy/không có báo trạng thái ngắn, không tạo kết quả thay thế. User vẫn thấy thông tin cá nhân, ảnh, trạng thái KYC và kết quả duyệt; reviewer mới thấy chi tiết kiểm tra trong lịch sử. **No liveness check** là ghi chú ngắn về phạm vi kiểm tra khuôn mặt.

## Kết quả và giới hạn

- **Local OCR:** Tesseract đọc tiếng Việt mặc định, có thể đổi sang English hoặc phối hợp hai ngôn ngữ. Trường tên/ngày sinh/số giấy tờ chỉ được gợi ý từ nhãn rõ ràng như `Họ và tên`, `Ngày sinh`, `Số CCCD` hoặc nhãn English tương ứng. Không suy đoán thông tin thiếu; không tự sửa chính tả tên. Ngày theo nhãn giấy tờ Việt Nam dùng `dd/mm/yyyy`; ISO cũng được hỗ trợ. Đây là OCR chữ in chung, chưa phải engine kiểm tra tính thật hoặc cấu trúc của mọi mẫu CCCD.
- Parser local chấp nhận một số lỗi nhãn phụ khi nhãn tiếng Việt còn rõ: `Ngày sinh / Dafe of birth: - 15/06/1995`, `Số/Ao-. 000000000000` và `SốCCCD` thiếu khoảng trắng. Chỉ loại dấu phân cách thừa trước ngày; giữ nguyên chữ số, khoảng trắng và số 0 đầu của số giấy tờ. Nhãn số điện thoại/số nhà/tài khoản, ngày hết hạn, nhiều ngày hoặc ký tự số chưa đọc rõ không được tự gán hay sửa. Confidence là trung bình toàn bộ từ OCR; `succeeded` nghĩa là có văn bản, không bảo đảm đã tách đủ field. Kết quả đã lưu/lịch sử giữ nguyên; với hồ sơ còn chỉnh sửa được, tải/chụp lại ảnh và Submit sẽ tạo lượt kiểm tra mới.
- **Local đối chiếu:** YuNet tìm khuôn mặt, SFace so sánh hai khuôn mặt đã căn chỉnh. `similarity` là cosine similarity ×100, giới hạn 0–100. Ngưỡng mặc định `36.3` dựa trên [ví dụ OpenCV](https://docs.opencv.org/4.x/d0/dd4/tutorial_dnn_face.html), tương ứng cosine `0.363`. Điểm này không phải phần trăm xác suất đúng danh tính, không so trực tiếp với AWS và cần đánh giá thêm trên ảnh thực tế của sản phẩm.
- **AWS OCR:** Textract trả văn bản và confidence trung bình theo dòng; parser chỉ gợi ý trường khi có nhãn English rõ ràng. [Textract hỗ trợ sáu ngôn ngữ](https://docs.aws.amazon.com/textract/latest/dg/limits-document.html), chưa hỗ trợ tiếng Việt/đầy đủ ký tự CCCD Việt Nam.
- Cả hai engine trả `selfieFace` độc lập với `faceMatch`. Selfie có `detected`, `no_face`, `multiple_faces` hoặc `failed`; đối chiếu có `matched`, `not_matched`, `no_face`, `multiple_faces` hoặc `failed`; OCR có `succeeded`, `no_text` hoặc `failed`. Selfie thiếu/nhiều khuôn mặt hoặc lỗi chặn bước đối chiếu; lỗi giấy tờ/đối chiếu không xóa kết quả phát hiện selfie đã thành công. Mỗi ảnh cần đúng một khuôn mặt để đối chiếu.
- OCR phụ thuộc độ rõ, ánh sáng, kích thước chữ và bố cục ảnh. Giấy tờ/ảnh selfie bị nghiêng, che khuất hoặc quá nhỏ có thể không nhận dạng được. Các kiểm tra hỗ trợ người duyệt, không tự phê duyệt/từ chối KYC, không kiểm tra giấy tờ thật và chưa có liveness/chống ảnh chụp lại.

## Lưu trữ và xử lý lỗi

Backend lấy ảnh riêng tư đã xác thực chủ sở hữu, giải mã trong bộ nhớ và giao cho provider. Local truyền ảnh qua stdin của tiến trình Python; Tesseract cũng đọc stdin, không tạo file ảnh plaintext tạm. Embeddings chỉ tồn tại trong bộ nhớ của lượt kiểm tra, không lưu vào database. Không log ảnh, OCR, lỗi provider hay credentials. Kết quả OCR/đối chiếu được mã hóa AES-256-GCM bằng khóa bảo vệ hồ sơ hiện có.

App gọi `POST /kyc/verification` trong lượt bấm Submit khi hồ sơ còn chỉnh sửa được, rồi mới gọi `POST /kyc/submit`. Hai bước giữ chung trạng thái đang nộp để ngăn bấm trùng. Kết quả đã hoàn tất hoặc provider bị tắt/không có cấu hình không tạo lượt kiểm tra mới. Lỗi dịch vụ kiểm tra không ngăn nộp cho reviewer; lỗi phiên/quyền hoặc ảnh/hồ sơ đã thay đổi dừng nộp và yêu cầu làm mới. Kết quả hoàn tất được dùng lại cho đúng hai media IDs, provider, ngưỡng và ngôn ngữ OCR local hiện tại. Đổi provider/ngưỡng/ngôn ngữ OCR local khiến hồ sơ đang chỉnh sửa cần kiểm tra lại; snapshot của lần nộp cũ vẫn giữ bằng chứng gốc. Kết quả local cũ chưa ghi ngôn ngữ cần chạy lại một lần. Chụp lại ảnh xóa kết quả đang làm việc; retry cùng capture ID giữ kết quả.

Bằng chứng cũ chưa có `selfieFace` không được suy ra là đã phát hiện khuôn mặt từ trạng thái đối chiếu chung. Hồ sơ đang chỉnh sửa cần chạy lại một lần; lịch sử reviewer cũ hiển thị **Not recorded** ở Selfie và giữ nguyên kết quả đối chiếu gốc.

Provider IO chạy ngoài transaction; backend kiểm tra lại media IDs/trạng thái trước khi lưu. Lượt kiểm tra có timeout tổng thể tối đa 8 giây, cooldown 30 giây và rate limit. Local timeout hủy cả nhóm tiến trình, bao gồm Tesseract. Runtime/model thiếu hoặc OCR cấu hình sai trả kết quả lỗi an toàn. Hồ sơ vẫn có thể nộp cho người duyệt khi kiểm tra không khớp/không khả dụng.

Migration `006_kyc_verification.sql` thêm cột nullable; hồ sơ/lịch sử trước tính năng không bị gán bằng chứng mới. Không cần migration khác cho local. Kết quả chạy thật trên máy phát triển và phạm vi kiểm chứng ở [local verification evidence](local-identity-verification-checks.md).
