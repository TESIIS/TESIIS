# 臺北市避難設施查詢系統

用地圖找出離你最近的避難收容處所。2025 臺北程式設計節城市通微服務大黑客松 團隊 30 作品。

**Clone 下來就能跑，不需要任何 API key。**

```bash
git clone <repo>
cd 2025Taipei-codefest-team30

# 後端
cd server && dart pub get && dart run bin/server.dart

# 前端（另開一個終端機）
cd flutter_codefest && flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/api
```

啟動後你應該看到後端印出：

```text
[DI] Coordinate table: data/shelter_coordinates.csv (380/401 shelters located, 94.8%)
✅ Server running on http://0.0.0.0:8080
```

---

## 這個專案在解什麼問題

臺北市有 401 處避難收容處所，資料公開在[臺北市資料大平臺](https://data.taipei/dataset/detail?id=aaf97773-3631-40e2-b3cc-da87bf2ce1d5)。但那份資料**沒有任何座標欄位**——只有「汀州路三段四號」這種門牌地址，沒辦法直接畫在地圖上。

本專案做三件事：

1. **補上座標。** 離線 join 兩個政府開放資料集，把 401 筆中的 380 筆定位出來（94.8%），成果進版控，所以任何人 clone 下來立刻可用。
2. **處理上游資料的怪癖。** 災害欄位不是單純 Y/N、里別分隔符不一致、數值欄位混雜中文說明——這些都在後端統一處理過。
3. **免金鑰的地圖。** 底圖用內政部國土測繪中心的免費 WMTS 服務，不需要 Google Cloud 帳號。

---

## 架構

兩個各自獨立的 Dart package，沒有共用 package 或 monorepo 工具。

```text
server/            Dart + shelf HTTP API
  bin/server.dart          唯一的 wiring 點
  lib/domain/entities/shelter_fields.dart   上游資料怪癖的單一處理點
  lib/data/datasources/local/coordinate_source.dart   座標表載入
  data/shelter_coordinates.csv              進版控的座標表（地圖的命脈）
  tool/build_coordinates.dart               離線重建座標表

flutter_codefest/  Flutter App
  lib/core/map/basemap.dart                 NLSC 底圖設定
  lib/presentation/pages/home_page.dart     單一畫面，所有地圖狀態
  lib/data/models/shelter.dart              對應後端的中文 JSON key
```

請求流：

```text
Flutter → ShelterController → ShelterService → ShelterRepositoryImpl
                                                 ├─ ShelterApi        (data.taipei，10 分鐘快取)
                                                 └─ CoordinateSource  (本地 CSV 座標表)
```

---

## 座標從哪裡來

這是整個專案最需要理解的一件事。

`server/data/shelter_coordinates.csv` 由 [`server/tool/build_coordinates.dart`](server/tool/build_coordinates.dart) 離線產生，流程：

```text
① 抓 臺北市可供避難收容處所一覽表        401 筆（無座標，這是要補的對象）
② 抓 消防署避難收容處所點位檔            全國 5973 筆，臺北市 272 筆（有經緯度）
③ 抓 北市警政APP_防空避難設備位置        6052 筆（有 座標x/座標y）
④ bbox 品質閘：座標落在臺北以外者一律丟棄
⑤ 以正規化門牌地址 join ② → 未命中者 join ③
⑥ 殘餘者用 Overpass 依名稱查（公園、捷運站…）
⑦ 再殘餘者用同路段最近門牌內插
```

重建：

```bash
cd server
dart run tool/build_coordinates.dart --report              # 只用官方資料
dart run tool/build_coordinates.dart --overpass --report   # 加上 OSM 補齊
dart run tool/build_coordinates.dart --refresh ...         # 忽略快取，重抓上游
```

### 座標品質（2026-08-09 實測）

| 來源 | 筆數 | 說明 |
|---|---|---|
| `nfa_point_file` | 251 | 消防署點位檔，同類設施，最可信 |
| `taipei_airraid` | 108 | 防空避難設備位置，同地址不同設施類別 |
| `osm_overpass` | 21 | OpenStreetMap 名稱比對（**ODbL**，見 [NOTICE.md](NOTICE.md)） |
| 無座標 | 21 | 門牌本身不是地址（「樂群一路旁基隆河截彎取直範圍內」） |

| 精度 | 筆數 | 意義 |
|---|---|---|
| `exact` | 285 | 正規化地址完全比對到政府資料集 |
| `name_match` | 6 | 以設施名稱比對 |
| `approx` | 89 | 依鄰近門牌推估，可能相差數十公尺 |

API 每筆回應都帶 `座標來源` 與 `座標精度`，App 會在介面上標示 `approx` 與無座標的情況——**不會假裝每個點都一樣精確**。

### 已知的上游資料錯誤

消防署點位檔的 272 筆臺北市資料中，有 2 筆座標離譜（`北市大附小` 標到屏東的 120.913/22.4797）。`TaipeiBounds` 品質閘會攔下來並列進報告。

---

## API

Base URL 預設 `http://localhost:8080/api`。

### `GET /shelters`

| 參數 | 中文別名 | 說明 |
|---|---|---|
| `q` | — | 關鍵字（在 server 本地比對名稱／地址／類型等欄位，多個關鍵字為 AND） |
| `city` | `縣市` | 支援「臺／台」兩種寫法 |
| `township` | `鄉鎮` | |
| `village` | `村里` | 同時比對「村里」與「服務里別」 |
| `villages` | — | 可重複或以分隔字元多值 |
| `type` | `類型` | |
| `flood` `quake` `landslide` `tsunami` | `水災` `震災` `土石流` `海嘯` | 值為 `Y`／`N`，或別名 `備用`／`老舊聚落` |
| `relief` `accessible` `indoor` `outdoor` | `救濟支站` `無障礙設施` `室內` `室外` | |
| `match` | — | `and`（預設）或 `or`，**僅作用在災害條件上** |
| `limit` `offset` | — | 套用在**過濾後**的結果 |

```json
{
  "success": true,
  "total": 401,
  "data": [{
    "收容所編號": "SA100-0002",
    "名稱": "臺北市立螢橋國民中學",
    "門牌地址": "汀州路三段四號",
    "震災": "Y",
    "服務里別": ["板溪里", "網溪里"],
    "座標x": 121.5265,
    "座標y": 25.019,
    "座標來源": "nfa_point_file",
    "座標精度": "exact"
  }]
}
```

### `GET /shelters/nearby?lat=&lng=&radius=&limit=`

依距離排序，距離計算在 server 端完成。額外回傳 `距離公尺`，以及 `excludedWithoutCoordinates`（因為沒有座標而排除的筆數，讓 client 知道清單不完整）。

```bash
curl 'localhost:8080/api/shelters/nearby?lat=25.0478&lng=121.5170&radius=800&limit=3'
```

### `GET /shelters/stats`

同一組過濾參數，回傳 `total`／`byType`／`byRegion`／`items`／`filters`，以及 `coordinateCoverage`：

```json
{ "total": 401, "withCoordinates": 380, "missing": 21, "ratio": 0.9476,
  "bySource": { "nfa_point_file": 251, "taipei_airraid": 108, "osm_overpass": 21, "none": 21 } }
```

---

## 設定

### server

`Env`（[`lib/core/config/env.dart`](server/lib/core/config/env.dart)）解析順序：**CLI 位置參數（僅 port） > 環境變數 > `.env` 檔 > 內建預設**。範本見 [`server/.env.example`](server/.env.example)。

| Key | 預設 | 說明 |
|---|---|---|
| `PORT` | `8080` | 也可用位置參數 `dart run bin/server.dart 3000` |
| `COORDINATES_CSV` | `data/shelter_coordinates.csv` | 座標表路徑 |
| `CACHE_TTL_SECONDS` | `600` | 上游資料快取時間 |
| `LOG_LEVEL` | `info` | `debug` \| `info` \| `warn` \| `error` |

不要直接讀 `Platform.environment`，一律走 `Env` 的 getter，否則優先序會不一致。

### flutter_codefest

**沒有任何金鑰要設定。** 唯一的建置期設定是後端位置：

```bash
flutter run   -d chrome --dart-define=API_BASE_URL=http://localhost:8080/api
flutter build web       --dart-define=API_BASE_URL=https://api.example.tw/api
```

- Android 模擬器連本機要用 `10.0.2.2`，不是 `localhost`。
- Flutter Web 若以 https 提供服務，後端也必須是 https，否則會被瀏覽器的 mixed-content 擋掉。

---

## 開發

```bash
# 後端
cd server
dart analyze        # 0 issues
dart test           # 85 passed

# 前端
cd flutter_codefest
flutter analyze     # 0 issues
flutter test        # 22 passed
```

CI（[`.github/workflows/ci.yml`](.github/workflows/ci.yml)）在每個 PR 跑 analyze、format、test、web build，以及 gitleaks 機密掃描。另有每週排程的 [upstream-data-check](.github/workflows/upstream-data-check.yml) 監看上游資料 schema 與覆蓋率變化。

貢獻前請讀 [CONTRIBUTING.md](CONTRIBUTING.md)，特別是**禁止提交清單**與安裝 pre-commit hook：

```bash
git config core.hooksPath .githooks
```

### 本機工具鏈現況

- Flutter 3.44 / Dart 3.12（pubspec 要求 sdk `^3.9.2`）
- 實務上可直接執行的目標是 `-d chrome` 與 macOS desktop
- iOS 需要 CocoaPods、Android 需要 Android SDK；本專案的 iOS/Android 設定（定位權限描述、entitlements、applicationId）已補齊但**未在本機實際建置驗證**

---

## 上游資料的已知特性

以下皆為 2026-08-09 對全部 401 筆的實測結果。這些規則的實作集中在 [`shelter_fields.dart`](server/lib/domain/entities/shelter_fields.dart)，**不要在別處重新實作**。

| 欄位 | 值域 |
|---|---|
| 水災 | Y(206) N(195) |
| 震災 | 備用(239) N(100) Y(62) |
| 土石流 | N(390) Y(6) 老舊聚落(5) |
| 海嘯 | N(391) 備用(10) — **完全沒有 Y** |
| 縣市 | 全部是 `臺北市`（「臺」不是「台」） |

- **災害欄位不是純 Y/N。** `備用` 與 `老舊聚落` 都代表「可用」，API 一律視為並輸出成 `Y`。海嘯沒有任何原生 `Y`，拿掉別名處理會讓 `?tsunami=Y` 永遠回 0 筆。若要單獨取出變體，用 `?quake=備用`。
- **`服務里別` 分隔符不一致**，除了 `、` 還混有 `。`、換行與括號註記。只切 `[、，,]` 會弄壞 4 筆。API 已正規化為陣列。
- **數值欄位是字串且不保證是數字。** `收容所面積（平方公尺）` 有千分位 `14,495` 與兩筆中文說明，`容納人數` 有一筆中文說明。
- **上游 `?q=` 完全無效**——`q=南港`、`q=zzzz` 都回全部 401 筆。真正的關鍵字過濾發生在 server 本地。
- **`match=or` 只作用在災害條件上**，region／type／keyword 永遠是 AND，且只評估查詢有帶到的災害鍵。

---

## 授權

程式碼以 **MIT** 授權（見 [LICENSE](LICENSE)）。

**資料檔另有授權**——`server/data/shelter_coordinates.csv` 混合了政府資料開放授權條款第 1 版與 ODbL（OpenStreetMap 部分）。再散布前請務必讀 [NOTICE.md](NOTICE.md)。

地圖底圖由**內政部國土測繪中心**提供，依其使用規範，顯示圖磚的畫面必須標示來源。App 已在地圖左下角標示，**請勿移除**。

> **本系統為查詢輔助工具，非官方災害應變系統。**
> 上游資料非即時，且部分座標為推估值。**災時請以臺北市政府即時公告為準。**

安全性問題請見 [SECURITY.md](SECURITY.md)，不要開公開 issue。

---

## 資料來源

- [臺北市可供避難收容處所一覽表](https://data.taipei/dataset/detail?id=aaf97773-3631-40e2-b3cc-da87bf2ce1d5) — 臺北市政府社會局
- [避難收容處所點位檔](https://data.gov.tw/dataset/73242) — 內政部消防署
- [北市警政APP_防空避難設備位置](https://data.taipei/dataset/detail?id=83eecdf1-3bbb-40f9-9484-b55b700c37ef) — 臺北市政府警察局
- [國土測繪圖資服務雲 WMTS](https://maps.nlsc.gov.tw/) — 內政部國土測繪中心
- [OpenStreetMap](https://www.openstreetmap.org/) — © OpenStreetMap contributors (ODbL)

---

## 團隊

臺北程式設計節城市通微服務大黑客松 2025 · 團隊 30 · 喵主餓餓女裝

- **@twcat0503**（台貓）
- **@nangong5421**（南宮柳信）
- **@itousouta15**（伊藤蒼太）
- **@yuzen9622**（Z）
- **@NiaN0412**（q_nnn412）
