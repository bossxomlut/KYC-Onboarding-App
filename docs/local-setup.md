# Cài đặt và khởi động dự án KYC trên macOS

Hướng dẫn này bao gồm cài công cụ, chạy các service, mở app, lấy OTP, dừng, khởi động lại và [xoá toàn bộ dữ liệu local](#9-xoá-toàn-bộ-dữ-liệu-local-và-chạy-lại-từ-đầu). Các lệnh minh họa dùng checkout hiện tại tại `/Users/vinhngo/KYC-Onboarding-App`; nếu checkout ở nơi khác, thay đường dẫn này.

## 1. Các thành phần cần chạy

| Thành phần   | Vai trò                                          | Địa chỉ local                       | Cách chạy                                     |
| ------------ | ------------------------------------------------ | ----------------------------------- | --------------------------------------------- |
| PostgreSQL   | Lưu tài khoản, phiên đăng nhập và hồ sơ KYC      | `127.0.0.1:5432`                    | `npm run db:local` hoặc Docker Compose        |
| Mailpit SMTP | Nhận email OTP/reset trong môi trường thử nghiệm | `127.0.0.1:1025`                    | Mailpit cài bằng Homebrew hoặc Docker Compose |
| Mailpit Web  | Xem nội dung email và mã OTP                     | <http://127.0.0.1:8025>             | Cùng tiến trình Mailpit SMTP                  |
| NestJS API   | Backend mà app gọi                               | `http://127.0.0.1:3000/api/v1`      | `npm run dev` trong `backend`                 |
| Flutter app  | Giao diện iOS/Android                            | Simulator, emulator hoặc điện thoại | `flutter run` trong `mobile`                  |

NestJS không tự khởi động PostgreSQL/Mailpit hoặc tự chạy migration. Email worker chạy bên trong NestJS, nên không cần mở một service worker riêng.

Chọn **một** cách chạy PostgreSQL/Mailpit:

- **Cách A: không Docker.** Phù hợp với môi trường đang dùng trên máy này; PostgreSQL lưu ở `backend/.local/postgres`.
- **Cách B: Docker Compose.** Chạy cả PostgreSQL và Mailpit bằng cấu hình trong repo; PostgreSQL lưu trong Docker named volume.

Hai cách sử dụng các nơi lưu dữ liệu khác nhau. Chuyển từ A sang B không tự chuyển tài khoản/ảnh/dữ liệu sang database mới. Không chạy hai cách đồng thời trên các cổng mặc định.

## 2. Cài công cụ một lần

### 2.1. Git và Homebrew

Cài Xcode Command Line Tools nếu máy chưa có Git/công cụ build:

```sh
xcode-select --install
```

Nếu chọn cách A, cài Homebrew theo [hướng dẫn chính thức](https://brew.sh/), thực hiện bước cấu hình `PATH` mà trình cài đặt hiển thị rồi mở terminal mới. Kiểm tra:

```sh
git --version
brew --version
```

### 2.2. Node.js và npm

Repo chọn Node **22** bằng `.nvmrc`; backend yêu cầu Node **22.12 trở lên**. npm được cài cùng Node. Cài nvm theo [hướng dẫn chính thức](https://github.com/nvm-sh/nvm#install--update-script), sau đó mở terminal mới và chạy:

```sh
cd /Users/vinhngo/KYC-Onboarding-App
nvm install
nvm use
node --version
npm --version
```

`nvm install`/`nvm use` đọc `.nvmrc` tại thư mục repo. Mỗi terminal mới chạy backend nên chạy lại `nvm use` từ thư mục repo. Nếu không dùng nvm, cài Node 22 từ [Node.js](https://nodejs.org/en/download) và kiểm tra `node --version`.

### 2.3. Flutter

Phiên bản đã kiểm tra với repo: **Flutter 3.44.6**, kèm **Dart 3.12.2**. Tải phiên bản này từ [Flutter SDK archive](https://docs.flutter.dev/install/archive), chọn macOS ARM64 cho Apple Silicon hoặc x64 cho Intel. Giải nén SDK theo [hướng dẫn cài thủ công](https://docs.flutter.dev/install/manual), ví dụ vào `$HOME/development/flutter`.

Thêm dòng sau vào `~/.zshrc` nếu SDK nằm ở vị trí ví dụ đó:

```sh
export PATH="$HOME/development/flutter/bin:$PATH"
```

Mở terminal mới, kiểm tra:

```sh
flutter --version
dart --version
flutter doctor -v
```

Dùng Dart đi kèm Flutter; đặt thư mục `flutter/bin` trước một Dart SDK cài riêng trong `PATH`. Trên máy hiện tại SDK nằm tại `/Users/vinhngo/development/flutter`.

### 2.4. Chạy iOS: Xcode và Simulator

Cài Xcode từ Mac App Store hoặc [Apple Developer](https://developer.apple.com/xcode/), mở Xcode để hoàn tất tải các thành phần. Cấu hình công cụ và đọc/chấp nhận giấy phép:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
sudo xcodebuild -license
```

Trong Xcode, cài iOS Simulator runtime ở Settings → Components/Platforms nếu thiếu, rồi mở Simulator:

```sh
open -a Simulator
flutter doctor -v
flutter devices
```

Repo hiện tích hợp plugin iOS bằng Swift Package Manager; chưa có `Podfile`, nên không cần chạy `pod install` cho cấu hình này. Nếu `flutter doctor` hoặc một plugin mới yêu cầu CocoaPods, cài theo [hướng dẫn CocoaPods](https://guides.cocoapods.org/using/getting-started.html#installation). Xem thêm [thiết lập iOS của Flutter](https://docs.flutter.dev/platform-integration/ios/setup).

### 2.5. Chạy Android: Android Studio và SDK

Cài [Android Studio](https://developer.android.com/studio), chạy Setup Wizard để cài Android SDK. Trong SDK Manager, cài Android SDK Platform **API 36** mà Flutter 3.44.6 dùng để compile, cùng SDK Build-Tools, Platform-Tools, Command-line Tools và Android Emulator. Gradle dùng NDK `28.2.13676358`; cài phiên bản đó trong SDK Tools nếu Gradle báo thiếu hoặc không tải được.

Trong Device Manager, tạo và khởi động một emulator; chọn system image ARM64 cho Mac Apple Silicon. App yêu cầu Android **API 24 trở lên**. Cấu hình Java của repo là 17; dùng JDK tương thích mà Android Studio cung cấp và kiểm tra bằng `flutter doctor -v`.

```sh
flutter doctor --android-licenses
flutter doctor -v
flutter devices
```

Đọc và chấp nhận các giấy phép cần thiết. Hướng dẫn chi tiết: [thiết lập Android của Flutter](https://docs.flutter.dev/platform-integration/android/setup).

## 3. Chuẩn bị dependency và cấu hình dự án

Chạy một lần khi cài mới, hoặc chạy lại các lệnh tải dependency sau khi lockfile thay đổi:

```sh
cd /Users/vinhngo/KYC-Onboarding-App
nvm use
node scripts/init-env.mjs
cd backend
npm ci
cd ../mobile
flutter pub get
```

`init-env.mjs` chỉ tạo `backend/.env` khi file chưa tồn tại; nó sinh ba khóa ngẫu nhiên riêng biệt và không in khóa. Nếu `.env` đã có, script giữ nguyên nội dung. Không chép đè `.env` khi khởi động lại: khóa `MEDIA_ENCRYPTION_KEY` cũ cần để đọc thông tin cá nhân và media đã lưu.

Các giá trị local mặc định trong `.env.example` khớp với hai cách chạy bên dưới: database `kyc`, user `kyc`, password mẫu `local-development-only`, port `5432`; SMTP `localhost:1025`; API port `3000`; `MEDIA_DIR=./media`. Khởi động backend từ thư mục `backend` để đường dẫn `.env` và media được resolve đúng.

### 3.1. Bật OCR và đối chiếu miễn phí

Cài Tesseract (`brew install tesseract`) và Python 3.11+, chạy `python3 scripts/setup-local-verification.py` từ thư mục gốc. Đặt `KYC_VERIFICATION_PROVIDER=local` và `KYC_FACE_MATCH_THRESHOLD=36.3` trong `backend/.env`, sau đó khởi động lại API. Engine chạy trên Mac/backend, không cần tài khoản AWS hay phí API. Xem [hướng dẫn OCR/đối chiếu](identity-verification.md) cho cấu hình và giới hạn.

## 4. Cách A — chạy không Docker

### Terminal 1: PostgreSQL

```sh
cd /Users/vinhngo/KYC-Onboarding-App
nvm use
cd backend
npm run db:local
```

Giữ terminal này chạy. Lần đầu package tải PostgreSQL binary phù hợp với máy, tạo database `kyc` và áp dụng migration. Các lần sau mở lại dữ liệu trong `backend/.local/postgres` và áp dụng migration còn thiếu. Không cần cài PostgreSQL riêng bằng Homebrew. Phiên bản embedded PostgreSQL của repo là 18.

Chờ dòng `Local PostgreSQL is ready on 127.0.0.1:5432; database kyc.` trước khi chạy API.

### Terminal 2: Mailpit

Cài một lần theo [hướng dẫn Mailpit](https://mailpit.axllent.org/docs/install/):

```sh
brew install mailpit
mailpit version
```

Khởi động Mailpit với địa chỉ loopback và hộp thư lưu bền vững trong thư mục local đã được Git ignore:

```sh
cd /Users/vinhngo/KYC-Onboarding-App
mkdir -p backend/.local
mailpit --listen 127.0.0.1:8025 --smtp 127.0.0.1:1025 \
  --database backend/.local/mailpit.db
```

Giữ terminal này chạy. Mở <http://127.0.0.1:8025>. `--database` giữ hộp thư qua các lần restart; không có tùy chọn này, Mailpit dùng database tạm. Xem [các tùy chọn runtime](https://mailpit.axllent.org/docs/configuration/runtime-options/).

Trên máy này, binary Mailpit tải cho các lần thử trước được giữ tại `backend/.local/tools/mailpit/mailpit` (Git ignore). Nếu chưa cài Mailpit qua Homebrew, có thể thay `mailpit` trong lệnh trên bằng `./backend/.local/tools/mailpit/mailpit`. Binary này chỉ có trên checkout hiện tại; khi clone repo mới, cài bằng Homebrew. Dừng phiên Mailpit cũ trước khi mở phiên mới để tránh chiếm cùng cổng.

### Terminal 3: NestJS API

```sh
cd /Users/vinhngo/KYC-Onboarding-App
nvm use
cd backend
npm run migrate
npm run admin:bootstrap
npm run dev
```

Giữ terminal này chạy; `tsx watch` tự nạp lại backend khi sửa source. Chờ dòng `KYC API listening on 0.0.0.0:3000`.

Để chạy bản JavaScript đã biên dịch thay cho dev watcher:

```sh
cd /Users/vinhngo/KYC-Onboarding-App
nvm use
cd backend
npm run build
npm start
```

### Terminal 4: Flutter app

Làm theo mục 6 bên dưới.

## 5. Cách B — chạy PostgreSQL và Mailpit bằng Docker

Cài [Docker Desktop cho Mac](https://docs.docker.com/desktop/setup/install/mac-install/), chọn Apple Silicon hoặc Intel đúng với máy; đưa app vào Applications và mở Docker Desktop. Docker Desktop đã kèm Docker Engine, CLI và [Compose](https://docs.docker.com/compose/install/).

Kiểm tra và khởi động từ thư mục chứa `compose.yaml`:

```sh
cd /Users/vinhngo/KYC-Onboarding-App
docker --version
docker compose version
docker compose up -d
docker compose ps
```

Chờ PostgreSQL hiển thị `healthy`; Mailpit phải ở trạng thái đang chạy. Compose của repo dùng PostgreSQL 17 và Mailpit, chỉ expose các cổng database/email vào localhost. Dữ liệu PostgreSQL ở named volume `kyc-postgres`, độc lập với `backend/.local/postgres` của cách A.

Trong một terminal khác, áp dụng migration rồi chạy API:

```sh
cd /Users/vinhngo/KYC-Onboarding-App
nvm use
cd backend
npm run migrate
npm run dev
```

Chạy mục 3 trước nếu chưa cài dependency/tạo `.env`. Sau đó mở thêm terminal để chạy Flutter theo mục 6. Mailpit trong Compose hiện chưa cấu hình hộp thư bền vững; nếu mất email sau khi restart, dùng Resend code trong app để nhận OTP mới.

## 6. Chạy app và kiểm tra kết nối

Trong terminal của Flutter:

```sh
cd /Users/vinhngo/KYC-Onboarding-App/mobile
flutter devices
```

Lấy ID thiết bị từ kết quả, thay chuỗi `ID_THIET_BI` trong **một** lệnh phù hợp:

```sh
# iOS Simulator
flutter run -d "ID_THIET_BI" \
  --dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1
```

```sh
# Android emulator
flutter run -d "ID_THIET_BI" \
  --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
```

`10.0.2.2` là địa chỉ máy host nhìn từ Android emulator. Không dùng `127.0.0.1` để gọi backend trên Mac từ Android emulator.

Với điện thoại thật, kết nối điện thoại và Mac cùng Wi-Fi, tìm IP Mac bằng `ipconfig getifaddr en0` hoặc Network settings, rồi thay ví dụ sau bằng IP thực:

```sh
flutter run -d "ID_THIET_BI" \
  --dart-define=API_BASE_URL=http://192.168.1.20:3000/api/v1
```

Cho phép API qua firewall và cấp quyền camera/local network khi được hỏi. iPhone thật cần thiết lập signing trong Xcode; Android thật cần bật Developer options/USB debugging. Release yêu cầu URL HTTPS; các lệnh local phía trên dùng Debug.

Kiểm tra API từ trình duyệt hoặc terminal:

```sh
curl http://127.0.0.1:3000/health
```

Khi API và database kết nối được, kết quả là `{"status":"ok"}`. Endpoint này kiểm tra kết nối database.

### Đăng ký và lấy OTP

1. Đăng ký trong app bằng email giả, ví dụ `maya@kyc.example`. Mật khẩu tối thiểu 12 ký tự, gồm chữ hoa, chữ thường và số.
2. Mở [Mailpit](http://127.0.0.1:8025).
3. Chọn email mới nhất gửi đến đúng địa chỉ vừa đăng ký; lấy mã 6 chữ số trong nội dung email.
4. Nhập mã vào app. OTP có hiệu lực 10 phút; Resend code có cooldown 30 giây.

Email local chỉ vào Mailpit, không gửi đến Gmail/hộp thư thật. Nếu chưa thấy email, kiểm tra Mailpit và API đều đang chạy; email worker sẽ thử gửi lại thư đang chờ. Sau restart Mailpit mà thư cũ đã mất hoặc OTP hết hạn, yêu cầu mã mới.

iOS Simulator không có camera thật. Để thử chụp ảnh, dùng Android emulator có camera hoặc điện thoại thật; dùng giấy tờ/ảnh giả cho assignment. Kiểm thử iOS với ảnh giả và cách tự quay video được mô tả trong [hướng dẫn demo](../demo/README.md).

### Admin và quyền duyệt hồ sơ

Sau khi database chạy, thực hiện `npm run migrate` và `npm run admin:bootstrap` trong `backend`. Email local mặc định `admin@kyc.com`; mật khẩu ngẫu nhiên lưu riêng trong `backend/.local/super-admin.json`, không in ra terminal. Chạy lại không reset tài khoản. Đăng nhập admin → **Manage accounts** để tạo tài khoản/cấp reviewer/xử lý yêu cầu; người dùng → **Account access** để xin quyền; reviewer → **Review profiles** để duyệt. Xem [hướng dẫn đầy đủ](admin-access.md).

## 7. Dừng và khởi động lại

### Cách A

Dừng Flutter bằng `q` trong terminal `flutter run`. Dừng NestJS, Mailpit và PostgreSQL bằng `Ctrl+C` tại terminal tương ứng. Các service này chạy ở foreground; hướng dẫn này chưa cấu hình tự bật khi khởi động máy.

Khi mở lại dự án, chạy lại các terminal theo thứ tự: **PostgreSQL → Mailpit → NestJS → Flutter**. Không cần cài lại công cụ hoặc tạo lại `.env`. `npm run db:local` mở dữ liệu cũ và tự áp dụng migration còn thiếu. Chỉ chạy lại `npm ci`/`flutter pub get` khi dependency thay đổi hoặc chưa được cài.

Nếu API chạy bằng `npm start` hoặc `node dist/server.js`, sau khi cập nhật backend phải dừng tiến trình API cũ, chạy `npm run build` trong `backend`, rồi `npm start`. Build chỉ cập nhật file trên ổ đĩa; tiến trình đang chạy vẫn dùng code đã nạp trước đó. Backend và app cần cùng contract review có `submissionId`; sau khi khởi động lại API, chọn **Retry** hoặc mở lại hồ sơ trong app. `/health` trả OK chỉ xác nhận kết nối database, không xác nhận phiên bản API.

### Cách B

Dừng Flutter/NestJS tại terminal của chúng, rồi từ repo chạy:

```sh
cd /Users/vinhngo/KYC-Onboarding-App
docker compose stop
```

Khởi động lại sau khi mở Docker Desktop:

```sh
cd /Users/vinhngo/KYC-Onboarding-App
docker compose up -d
docker compose ps
```

Sau khi PostgreSQL healthy, chạy `npm run migrate` trong `backend` để áp dụng migration mới nếu có, rồi mở lại NestJS/Flutter. [`stop`](https://docs.docker.com/reference/cli/docker/compose/stop/) giữ các container; [`down`](https://docs.docker.com/reference/cli/docker/compose/down/) xóa container/network nhưng mặc định giữ named volume. **Không dùng `down -v` để dừng thường ngày** vì tùy chọn đó xóa volume database.

## 8. Dữ liệu nằm ở đâu và công cụ xem

| Dữ liệu                       | Vị trí                                              |
| ----------------------------- | --------------------------------------------------- |
| Cấu hình và khóa local        | `backend/.env` — Git ignore, không chia sẻ nội dung |
| PostgreSQL cách A             | `backend/.local/postgres`                           |
| PostgreSQL cách B             | Docker named volume `kyc-postgres`                  |
| Media của cả hai cách         | `backend/media` khi API được chạy từ `backend`      |
| Mailpit cách A theo lệnh trên | `backend/.local/mailpit.db`                         |

DBeaver là công cụ xem database tùy chọn; cài từ [trang chính thức](https://dbeaver.io/download/). Kết nối PostgreSQL với host `127.0.0.1`, port `5432`, database `kyc`, username `kyc`, password mẫu `local-development-only`. Các bảng ở `Schemas → public → Tables`.

Ảnh trên ổ đĩa có tên UUID, nội dung mã hóa, không thể mở bằng cách đổi đuôi `.jpg`. Bảng `kyc_media.storage_key` tham chiếu tới tên file. Xem ảnh qua Review trong app hoặc API có access token của chủ ảnh; backend giải mã và trả JPEG. Khi reset, xoá cả database và media theo mục 9 để không còn tham chiếu tới ảnh đã bị xoá.

## 9. Xoá toàn bộ dữ liệu local và chạy lại từ đầu

Các lệnh dưới đây xoá tài khoản, mật khẩu/OTP, phiên đăng nhập, hồ sơ KYC, lịch sử nộp/duyệt, quyền/audit, ảnh upload và email thử nghiệm. Sau đó đăng ký tài khoản mới từ đầu. Việc dọn repo ngày 11/10/2026 chưa chạy các lệnh reset này.

### 9.1. Đăng xuất và dừng dịch vụ

1. **Logout thành công trên các thiết bị khi API còn chạy.** Bước này xoá refresh token trong secure storage, đặc biệt cần cho iOS vì Keychain có thể còn sau khi gỡ app.
2. Dừng `flutter run` bằng `q`; đóng app trên thiết bị.
3. Dừng API, PostgreSQL embedded và Mailpit bằng `Ctrl+C` ở terminal tương ứng. Nếu dùng Docker, dừng API rồi làm bước Docker bên dưới.
4. Với cách A, kiểm tra không còn service local nghe các cổng trước khi xoá:

```sh
lsof -nP -iTCP:3000 -iTCP:5432 -iTCP:1025 -iTCP:8025 -sTCP:LISTEN
```

Nếu còn tiến trình của dự án, dừng đúng tiến trình đó trước. Không xoá thư mục PostgreSQL hoặc file Mailpit khi service đang chạy.

### 9.2. Xoá dữ liệu backend

**Cách A đang dùng trên máy này: PostgreSQL embedded và Mailpit trực tiếp.** Chạy từ thư mục gốc repo sau khi đã dừng service:

```sh
cd /Users/vinhngo/KYC-Onboarding-App
rm -rf backend/.local/postgres \
  backend/.local/runner-smoke \
  backend/.local/identity-smoke \
  backend/media
rm -f backend/.local/super-admin.json \
  backend/.local/mailpit.db \
  backend/.local/mailpit.db-wal \
  backend/.local/mailpit.db-shm \
  backend/.local/mailpit.log
```

Xoá cả `super-admin.json` để bootstrap tạo mật khẩu mới cho database mới. Giữ `backend/.env`, `.local/identity-models`, `.local/identity-venv` và `.local/tools`: đây là cấu hình/công cụ, không phải dữ liệu người dùng. Không cần cài lại Node, Flutter hoặc OCR chỉ để reset dữ liệu.

**Cách B nếu dùng Docker Compose:** chạy từ cùng repo và cùng Compose project đã dùng lúc khởi động:

```sh
cd /Users/vinhngo/KYC-Onboarding-App
docker compose down --volumes
```

[`down --volumes`](https://docs.docker.com/reference/cli/docker/compose/down/) xoá volume PostgreSQL của Compose và container Mailpit. Sau đó chạy khối `rm` của cách A để xoá media, credentials và dữ liệu embedded/Mailpit cũ nếu đã từng dùng cả hai cách. Không dùng lệnh prune toàn bộ Docker.

Các đường dẫn trên khớp cấu hình local hiện tại. Nếu đã đổi `MEDIA_DIR`, dùng `LOCAL_DATABASE_DIR` khi khởi động database, hoặc chọn database khác trong `DATABASE_URL`, phải reset đúng nơi lưu dữ liệu đó. `db:local` đọc `LOCAL_DATABASE_DIR` từ biến môi trường terminal, không tự đọc `.env`.

### 9.3. Xoá dữ liệu app trên thiết bị

**Android emulator hoặc điện thoại Android:** lấy ID từ `adb devices`, thay `ID_THIET_BI` rồi chạy:

```sh
adb devices
adb -s "ID_THIET_BI" shell pm clear com.example.kyc_onboarding
```

Lệnh [`pm clear`](https://developer.android.com/tools/adb) xoá dữ liệu app, token và ảnh tạm; thành công trả `Success`. Không cần gỡ APK. Làm trên từng thiết bị đã dùng.

**iOS Simulator:** sau khi Logout thành công, gỡ app trên simulator đang mở:

```sh
xcrun simctl uninstall booted com.example.kycOnboarding
```

Nếu có nhiều simulator đang boot, thay `booted` bằng UUID từ `xcrun simctl list devices booted`. **iPhone thật:** Logout rồi chọn **Delete App**, không dùng Offload App. Logout xoá token; gỡ app xoá sandbox/ảnh tạm. [Keychain có thể còn sau uninstall](https://developer.apple.com/forums/thread/36442), nên gỡ app một mình chưa bảo đảm xoá token. Nếu đã xoá server trước khi Logout, khởi động API mới rồi mở app cũ: refresh token hết hiệu lực sẽ được app xoá khi server trả lỗi xác thực; sau đó gỡ/cài lại. Không cần reset toàn bộ simulator.

### 9.4. Khởi động với dữ liệu trống

1. Tại repo, chạy `nvm use` (hoặc `nvm install` nếu chưa có Node 22), `node scripts/init-env.mjs`. Script giữ cấu hình hiện có.
2. Nếu thiếu dependency backend, chạy `npm ci` trong `backend` trước, dù chọn cách A hay B. **Terminal PostgreSQL:** `cd backend` rồi `npm run db:local`; chờ thông báo ready. Nó tạo database mới và áp dụng migration. Với Docker, thay bước này bằng `docker compose up -d` tại repo và chờ PostgreSQL healthy.
3. **Terminal Mailpit (cách A):** chạy lệnh mục 4, hoặc tại repo dùng binary `./backend/.local/tools/mailpit/mailpit` như hướng dẫn. Với Docker, Mailpit đã chạy ở bước 2.
4. **Terminal API:** tại repo chạy `nvm use`, vào `backend`, lần lượt chạy:

```sh
npm run migrate
npm run admin:bootstrap
npm run dev
```

5. Kiểm tra `curl http://127.0.0.1:3000/health` trả `{"status":"ok"}`. Email admin mặc định là `admin@kyc.com` (trừ khi đã đặt `BOOTSTRAP_ADMIN_EMAIL`); mật khẩu mới ở `backend/.local/super-admin.json`.
6. **Terminal Flutter:** vào `mobile`, chạy `flutter pub get`, rồi lệnh `flutter run` đúng thiết bị ở mục 6. Đăng ký email thử nghiệm mới; lấy OTP trong Mailpit. Không chạy `npm run demo` nếu muốn quay từ bước tự đăng ký.

Database vừa tạo không còn tài khoản/hồ sơ cũ; sau bootstrap chỉ có admin và dữ liệu khởi tạo của admin. Hộp thư Mailpit trống trước khi đăng ký mới.

Nếu muốn cài lại cả cấu hình/OCR, chỉ sau khi đã xoá toàn bộ dữ liệu và dừng service mới xoá `backend/.env` và `backend/.local`; chạy lại `init-env.mjs` và mục 3.1 để cài/bật OCR. Việc này cũng xoá binary Mailpit local, nên cần cài Mailpit bằng Homebrew. Reset dữ liệu thông thường không cần bước này.

## 10. Lỗi thường gặp

| Hiện tượng                                             | Kiểm tra và xử lý                                                                                                                                                                        |
| ------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `nvm`, `node`, `flutter` hoặc `mailpit` không tìm thấy | Kiểm tra đã cài công cụ, cấu hình `PATH`, mở terminal mới; dùng `nvm use` tại repo                                                                                                       |
| Cổng `5432` bị chiếm                                   | Kiểm tra có đang chạy PostgreSQL cách A hoặc Docker trước đó; chọn một instance. Cách A hỗ trợ `LOCAL_DATABASE_PORT=5433 npm run db:local`, nhưng phải cập nhật `DATABASE_URL` tương ứng |
| Cổng `1025` hoặc `8025` bị chiếm                       | Có Mailpit foreground, binary demo, Homebrew service hoặc Docker đang chạy; dừng đúng instance không dùng                                                                                |
| Cổng `3000` bị chiếm                                   | API cũ vẫn chạy; dừng terminal cũ trước khi chạy lại                                                                                                                                     |
| `Cannot connect to the Docker daemon`                  | Mở Docker Desktop, chờ Engine hoạt động rồi thử lại                                                                                                                                      |
| API lỗi kết nối database                               | Chờ database ready/healthy; đối chiếu host, port và database trong cấu hình local                                                                                                        |
| App báo không kết nối được API                         | Kiểm tra đúng URL theo iOS/Android/điện thoại thật, đúng `/api/v1`, và firewall                                                                                                          |
| Admin mở Review identity gặp lỗi chung sau cập nhật app | Kiểm tra API đang chạy là bản mới: chi tiết review phải có `submissionId`. Dừng API cũ, build và khởi động lại theo mục 7, rồi chọn Retry trong app                                      |
| Không có OTP trong Gmail                               | Email thử nghiệm nằm trong Mailpit; mở port `8025`, kiểm tra đúng người nhận                                                                                                             |
| Đăng ký lại cùng email bị từ chối                      | Tài khoản đã được tạo, kể cả chưa xác thực; dùng đăng nhập hoặc gửi lại OTP                                                                                                              |
| Build iOS/Android thiếu SDK hoặc license               | Chạy `flutter doctor -v`, hoàn thành mục tương ứng; Android dùng `flutter doctor --android-licenses`                                                                                     |
| Không đọc được media/draft cũ sau khi đổi cấu hình     | Kiểm tra database, thư mục media và khóa mã hóa có thuộc cùng bộ dữ liệu; không tạo khóa mới để thay khóa cũ                                                                             |

Để xác định tiến trình đang giữ một cổng trên macOS, ví dụ Mailpit Web:

```sh
lsof -nP -iTCP:8025 -sTCP:LISTEN
```

Sau khi môi trường sẵn sàng, xem [README](../README.md) cho chức năng review và lệnh test/build, [backend guide](backend.md) cho API và [verification](verification.md) cho phạm vi đã kiểm chứng. Hướng dẫn này không yêu cầu cung cấp credentials production hoặc dữ liệu KYC thật cho công cụ AI.
