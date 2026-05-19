# VCamJoy iOS — Build không cần Mac

## Cách build qua GitHub Actions (miễn phí, không cần Mac)

### Bước 1: Tạo GitHub repo
1. Vào https://github.com → "New repository"
2. Đặt tên: `vcamjoy-ios` → Create repository

### Bước 2: Upload code
Upload toàn bộ thư mục này lên repo vừa tạo.
Có thể dùng GitHub Desktop (https://desktop.github.com) cho dễ.

Cấu trúc phải đúng như sau:
```
vcamjoy-ios/
├── .github/
│   └── workflows/
│       └── build.yml
├── VCamJoy/
│   ├── VCamJoy.xcodeproj/
│   │   └── project.pbxproj
│   └── Sources/
│       ├── main.m
│       ├── AppDelegate.h / .m
│       ├── MainViewController.h / .m
│       ├── VCamReceiver.h / .m
│       └── Info.plist
└── entitlements.plist
```

### Bước 3: Trigger build
- Vào tab **Actions** trong repo
- Click **"Build VCamJoy IPA"** → **"Run workflow"** → Run
- Đợi ~5 phút

### Bước 4: Download IPA
- Sau khi build xong → click vào run vừa chạy
- Cuộn xuống **Artifacts** → Download **VCamJoy-IPA**
- Giải nén → có file `VCamJoy.ipa`

### Bước 5: Cài lên phone JB
```bash
# Qua SSH (phone và PC cùng mạng WiFi)
scp VCamJoy.ipa root@192.168.x.x:/var/mobile/

ssh root@192.168.x.x
# Giải nén IPA → cài app
mkdir -p /Applications/VCamJoy.app
cd /tmp && unzip /var/mobile/VCamJoy.ipa
cp -r Payload/VCamJoy.app/* /Applications/VCamJoy.app/
ldid -S/Applications/VCamJoy.app/VCamJoy
uicache
```

Hoặc dùng **Filza** trên phone:
1. Copy IPA vào phone qua AirDrop / Files
2. Mở Filza → tìm file IPA → "Install"

---

## Cách dùng sau khi cài

1. Chạy `START_SERVER.bat` trên PC
2. Mở app **VCamJoy** trên phone
3. Nhập IP của PC (hiện trong terminal) + port 8080
4. Bấm **"Kết nối"** → thấy preview stream
5. Bật switch **"Virtual Camera"**
6. Mở **Camera app** → thấy video từ PC

## Hỗ trợ
- iOS 15.0 – 16.x
- JB: Palera1n, Dopamine, XinaA15
- Hoạt động với: Camera, FaceTime, Instagram, TikTok, Discord
