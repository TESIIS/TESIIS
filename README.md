# 北市避難設施資訊整合系統

一個以 **Flutter** 打造的地圖式避難設施查詢 App，搭配 **Dart/shelf** 後端 API 伺服器，整合搜尋、分類、距離計算、導航與告示提醒功能。

> 本專案為 **臺北程式設計節城市通微服務大黑客松 2025** 團隊編號 30 之參賽作品。

---

## 專案架構

```
2025codefestteam30/
├── flutter_codefest/          # Flutter 前端 App
│   ├── lib/
│   │   ├── main.dart                          # App 進入點
│   │   ├── presentation/pages/
│   │   │   ├── home_page.dart                 # 地圖主畫面與所有 UI 互動
│   │   │   └── user_manual_page.dart          # 使用手冊頁面
│   │   ├── core/utils/nearby_shelters.dart    # 附近設施計算邏輯
│   │   ├── data/models/
│   │   │   ├── shelter.dart                   # 避難設施資料模型
│   │   │   ├── api_response.dart              # API 回應模型
│   │   │   └── filter_model.dart              # 篩選條件模型
│   │   ├── data/datasources/api.dart          # HTTP API 客戶端
│   │   └── data/repositories/shelters_repository.dart  # 設施資料儲存庫
│   ├── pubspec.yaml
│   └── web/ android/ ios/ ...                 # 各平台工程
│
├── server/                    # Dart/shelf 後端 API
│   ├── bin/server.dart                        # 伺服器進入點
│   ├── lib/
│   │   ├── core/                              # 核心模組（config、DI、logger、errors）
│   │   ├── domain/                            # 領域層（entities、repositories、services）
│   │   ├── data/                              # 資料層（datasources、repositories_impl、models）
│   │   ├── presentation/                      # 表現層（routes、controllers、middlewares、responses）
│   │   └── utils/                             # 工具類別
│   ├── test/                                  # 單元測試與整合測試
│   └── pubspec.yaml
│
└── README.md                  # 本檔案
```

---

## 特色功能

- **Google 地圖互動檢視**：全螢幕地圖，不隨鍵盤上移
- **即時定位**：顯示目前位置與 1.5 公里範圍圈
- **搜尋與篩選**：支援關鍵字搜尋與多選分類篩選（災害類型：土石流／海嘯／地震／水災；空間：室內／室外）
- **分類按鈕列**：可左右滑動，兩側白色漸變提升可見度
- **底部面板**：常駐顯示最近設施（約佔螢幕 25%），含名稱、地址、距離、類別標籤、快速導航與詳情按鈕
- **使用手冊**：書本按鈕固定於右下角，隨時查看操作說明
- **告示提醒**：
  - 超出台北市範圍 → 橘色橫幅
  - 定位成功 → 綠色橫幅（3 秒自動隱藏）
  - 定位失敗 → 紅色橫幅
  - 桌面寬螢幕 → 藍色提示建議使用手機比例
- **後端 API**：從台北市 OpenData 擷取「避難收容處」資料，提供列表查詢與統計彙整 API
- **Geocoding 快取**：伺服器端保留 SQLite 地理編碼索引以補足座標資料並加速查詢

---

## 環境需求

### 前端（Flutter App）
- Flutter SDK 3.9.x（或相容版本）
- Dart SDK（隨 Flutter 一併安裝）
- Android Studio 或 Xcode（依目標平台而定）
- Google Maps API Key（Android / iOS / Web 皆需配置）

### 後端（Dart Server）
- Dart SDK 3.9.x
- 無需資料庫（使用 SQLite 本地檔案 + 台北市 OpenData API）

---

## 主要套件

### Flutter 前端
| 套件 | 用途 |
|------|------|
| `google_maps_flutter` | 地圖顯示 |
| `geolocator` | 取得使用者定位 |
| `permission_handler` | 權限請求 |
| `flutter_svg` | SVG 圖示渲染 |
| `url_launcher` | 開啟 Google 地圖導航 |
| `http` | HTTP 請求後端 API |

### Dart 後端
| 套件 | 用途 |
|------|------|
| `shelf` | HTTP 伺服器中介軟體 |
| `shelf_router` | 路由 |
| `shelf_cors_headers` | CORS 跨域支援 |
| `http` | 向 OpenData API 發起請求 |
| `sqlite3` | 本地地理編碼資料庫 |
| `json_annotation` / `json_serializable` | JSON 序列化 |
| `get_it` | 依賴注入 |
| `logging` | 日誌紀錄 |

---

## 快速開始

### 1. 啟動後端伺服器

```powershell
# 進入伺服器目錄
cd server

# 安裝相依套件
dart pub get

# 啟動伺服器（預設埠 8080）
dart run bin/server.dart

# 指定埠（例如 3000）
dart run bin/server.dart 3000

# 或使用環境變數
$env:PORT = "3000"; dart run bin/server.dart
```

伺服器啟動後，可透過 `http://localhost:8080/api/shelters` 測試 API。

### 2. 啟動前端 App

```powershell
# 進入 Flutter 專案目錄
cd flutter_codefest

# 安裝相依套件
flutter pub get

# 執行（裝置／模擬器需就緒）
flutter run

# 指定平台
flutter run -d chrome           # Web
flutter run -d android          # Android
flutter run -d ios              # iOS（需 macOS + Xcode）
flutter run -d windows          # Windows 桌面
```

> **注意**：啟動前請先完成 Google Maps API Key 設定（見下節），否則地圖將顯示為空白。

---

## Google Maps API Key 設定

請依平台設定地圖金鑰：

### Android
在 `flutter_codefest/android/app/src/main/AndroidManifest.xml` 的 `<application>` 內加入：
```xml
<meta-data android:name="com.google.android.geo.API_KEY"
           android:value="YOUR_ANDROID_API_KEY" />
```

### iOS
在 `flutter_codefest/ios/Runner/AppDelegate.swift` 中呼叫：
```swift
GMSServices.provideAPIKey("YOUR_IOS_API_KEY")
```
或於 `Info.plist` 設定對應 Key。

### Web
在 `flutter_codefest/web/index.html` 中，於 Google Maps JavaScript API 的 `key` 參數帶入金鑰：
```html
<script src="https://maps.googleapis.com/maps/api/js?key=YOUR_WEB_API_KEY"></script>
```

---

## 權限設定

### Android
在 `AndroidManifest.xml` 加入：
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.INTERNET" />
```

### iOS
在 `Info.plist` 加入用途說明：
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>需要使用您的位置以顯示附近避難設施</string>
```

---

## 後端 API 文件

伺服器提供以下端點，Base URL 為 `http://localhost:<PORT>/api`。

### GET `/api/shelters`

取得符合條件的避難收容處列表。

**查詢參數：**

| 參數 | 說明 |
|------|------|
| `q` | 關鍵字（支援多個字詞，以空白、逗號或頓號分隔） |
| `city` / `縣市` | 縣市名稱 |
| `township` / `鄉鎮` | 鄉鎮行政區 |
| `village` / `村里` | 單一村里 |
| `villages` | 多個村里，可重複或逗號分隔 |
| `type` / `類型` | 避難場所類型 |
| `flood`, `quake`, `landslide`, `tsunami`, `relief`, `accessible`, `indoor`, `outdoor` | 災害與設施條件（值為 `Y` / `N`） |
| `match` | `and`（預設）或 `or`，決定多條件組合方式 |
| `limit` | 回傳筆數上限（預設 1000） |
| `offset` | 分頁起點 |

**成功回應：**
```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "名稱": "...",
      "縣市": "台北市",
      "鄉鎮": "中正區",
      "村里": "...",
      "服務里別": ["..."],
      "類型": "...",
      "水災": "Y",
      "室內": "Y",
      "容納人數": 200,
      "座標x": 121.5,
      "座標y": 25.0
    }
  ],
  "total": 123,
  "filters": { ... }
}
```

**失敗回應：**
```json
{
  "success": false,
  "message": "錯誤描述",
  "code": "可選的錯誤代碼"
}
```

### GET `/api/shelters/stats`

在相同查詢條件下提供統計資訊與行政區彙整。

**查詢參數：** 與 `/api/shelters` 相同。

**成功回應：**
```json
{
  "success": true,
  "filters": { "q": "南港", "city": "台北市", "match": "and" },
  "total": 45,
  "byType": [{ "type": "國中小", "count": 20 }],
  "byRegion": [
    {
      "city": "台北市",
      "total": 45,
      "townships": [
        {
          "township": "南港區",
          "total": 30,
          "villages": [{ "village": "三重里", "count": 5 }],
          "shelters": [{ "名稱": "...", "門牌地址": "..." }]
        }
      ]
    }
  ],
  "items": [
    { "名稱": "...", "門牌地址": "...", "縣市": "台北市", "鄉鎮": "南港區", "村里": "..." }
  ]
}
```

---

## 環境變數

### 後端伺服器

| 變數 | 說明 | 預設值 |
|------|------|--------|
| `PORT` | HTTP 伺服器監聽埠 | `8080` |
| `GEOCODING_DB` | Geocoding SQLite 檔案路徑 | `lib/data/datasources/database/geoapify_results.db` |
| `LOG_LEVEL` | 日誌等級（debug / info / warn / error） | `info` |

設定範例（PowerShell）：
```powershell
$env:PORT = "3000"
$env:GEOCODING_DB = "D:\data\geoapify_results.db"
```

### 前端 Flutter App
前端 App 的 API 連線位址定義於 `flutter_codefest/lib/data/datasources/api.dart`：
```dart
static const String baseUrl = 'http://localhost:8080/api';
```
請依您的後端部署位置修改此值。

---

## 使用說明

- **搜尋與分類**：開啟搜尋後，顯示可左右滑動的分類按鈕，可複選
- **篩選邏輯**：符合任一選擇的類型即會顯示（OR 行為）
- **底部面板**：畫面底部常駐約 25% 高度，提供「開始導航」與「詳情」按鈕
- **提醒橫幅**：
  - 超出台北市 → 橘色告示
  - 定位成功 → 綠色（3 秒自動隱藏）/ 失敗 → 紅色
  - 桌面寬度 > 600px → 藍色提示建議使用手機比例
- **使用手冊**：右下書本按鈕可進入使用手冊頁面

---

## 常見問題（FAQ）

- **地圖不顯示／一片空白**
  - 請確認已正確設定 Google Maps API Key，且金鑰未受限於不相容的網域或金鑰類型。
- **要求定位權限被拒**
  - Android：到系統設定開啟 App 定位權限並重試。
  - iOS：到設定 > 隱私權 > 定位服務開啟對應權限。
- **模擬器定位不準**
  - 請在模擬器工具中手動設定 GPS 座標，或改用實機測試。
- **後端啟動失敗（SocketException: errno = 10048）**
  - 埠被占用，請使用 `netstat -ano | findstr :<port>` 找出佔用程序並處理，或改用其他埠啟動。

---

## 開發指令

```powershell
# Flutter：清除建置快取
cd flutter_codefest; flutter clean

# Flutter：檢查相依更新
flutter pub outdated

# Flutter：執行測試
flutter test

# 後端：執行測試
cd server; dart test

# 後端：分析程式碼
dart analyze
```

---

## 資料來源

- **台北市 OpenData**：`https://data.taipei/api/v1/dataset`
  - 資料集 ID：`4c92dbd4-d259-495a-8390-52628119a4dd`（北市警政 APP_防空避難設備位置）

---

## 版權與授權

本專案僅供教學與競賽展示用途，保留所有權利。若需商業或長期維運使用，請務必檢視第三方套件授權與 Google Maps API 使用條款。

---

## 參與開發

- **@twcat0503**（台貓）
- **@nangong5421**（南宮柳信）
- **@itousouta15**（伊藤蒼太）
- **@yuzen9622**（Z）
- **@NiaN0412**（q_nnn412）

---

## 臺北程式設計節城市通微服務大黑客松 2025

- 團隊編號：30
- 隊名：喵主餓餓女裝
