# TESIIS 臺灣避難收容處所資訊整合系統

獨立運作的 Flutter Web，用地圖找出離你最近的避難收容處所，涵蓋全臺 22 縣市。源自 2025
臺北程式設計節城市通微服務大黑客松團隊 30 作品（原本只涵蓋臺北市 401 筆）；目前不依賴
臺北通 SDK、登入狀態或內嵌容器，可直接以一般瀏覽器開啟。

**Clone 下來就能跑，不需要任何 API key。**

## Docker 啟動（建議）

```bash
git clone https://github.com/Twcat0503/2025Taipei-codefest-team30.git
cd 2025Taipei-codefest-team30
docker compose up --build
```

開啟 <http://localhost:8080>。對外只有一個 Web port：Nginx 提供 Flutter
靜態檔，並把同源的 `/api/*` 轉送到內部 Dart API。健康檢查：

```bash
curl http://localhost:8080/healthz
docker compose ps
```

停止服務：

```bash
docker compose down
```

若 8080 已被占用，可用 `WEB_PORT=8088 docker compose up --build`。

## 不使用 Docker 的本機開發

```bash
# Clone 後進入 repo 根目錄

# 後端
cd server && dart pub get && dart run bin/server.dart

# 前端（另開一個終端機）
cd flutter_codefest && flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/api
```

啟動後你應該看到後端印出：

```text
[DI] Nationwide snapshot: data/shelters_nationwide.csv (5854 shelters, 22 counties, updated ...)
✅ Server running on http://0.0.0.0:8080
```


## 這個專案在解什麼問題

全臺 22 縣市有 5,973 處避難收容處所，資料公開在[消防署避難收容處所點位檔](https://data.gov.tw/dataset/73242)，已含經緯度。本專案：

1. **驗證座標品質。** 單一全國 bounding box 沒有意義（會誤放某縣市座標到別的地方去），改用逐縣市 22 組 box 驗證，5,854 筆（98.0%）通過，成果進版控，任何人 clone 下來立刻可用。
2. **處理上游資料的怪癖。** 災害欄位不是單純 Y/N（NFA 用「是／否」）、里別分隔符不一致、數值欄位混雜中文說明——這些都在後端統一處理過。
3. **免金鑰的地圖。** 底圖用內政部國土測繪中心的免費 WMTS 服務，不需要 Google Cloud 帳號。

## 架構

兩個各自獨立的 Dart package，由 Docker Compose 組成單一對外 Web 服務。

```text
server/            Dart + shelf HTTP API
  bin/server.dart          唯一的 wiring 點
  lib/domain/entities/shelter_fields.dart   臺北市 OpenData 怪癖的處理點
  lib/data/mappers/nfa_shelter_mapper.dart  全國點位檔 → Shelter 的正規化
  lib/core/geo/taiwan_bounds.dart           22 縣市座標品質閘門
  lib/data/datasources/local/shelter_snapshot_source.dart   全國快照載入
  data/shelters_nationwide.csv              進版控的全國快照（地圖的命脈）
  tool/build_nationwide_snapshot.dart       離線重建全國快照
  data/shelter_coordinates.csv              臺北市專屬座標表（次要資料源）
  tool/build_coordinates.dart               離線重建臺北市座標表

flutter_codefest/  Flutter App
  lib/core/map/basemap.dart                 NLSC 底圖設定
  lib/domain/marker_clustering.dart         marker 分簇（避免全國搜尋爆量）
  lib/presentation/pages/map_page.dart      單一畫面，所有地圖狀態
  lib/data/models/shelter.dart              對應後端的中文 JSON key
```

請求流：

```text
Browser → Nginx :8080 ─┬─ Flutter Web 靜態檔
                       └─ /api/* → Dart API :8080（僅容器內部）
                                      └─ ShelterRepositoryImpl
                                           ├─ NfaShelterApi (消防署點位檔，10 分鐘快取)
                                           └─ ShelterSnapshotSource (本地全國快照，upstream 失敗或看起來不合理時的備援)
```

Nginx 明確送出 `X-Frame-Options: DENY` 與 `frame-ancestors 'none'`，正式版是
獨立網站，不應再嵌入臺北通或其他 iframe。全國化方案見
[`docs/nationwide-roadmap.md`](docs/nationwide-roadmap.md)。

## 座標從哪裡來

這是整個專案最需要理解的一件事。

`server/data/shelters_nationwide.csv` 由 [`server/tool/build_nationwide_snapshot.dart`](server/tool/build_nationwide_snapshot.dart) 離線產生，流程比臺北市時期單純很多，因為消防署點位檔本身就有座標，不需要 join：

```text
① 抓 消防署避難收容處所點位檔    全國 5973 筆（已含 經度/緯度）
② 逐筆用 22 縣市各自的 bounding box 驗證座標合理性（金門縣因烏坵鄉飛地需要兩個 box）
③ 產生確定性 ID（NFA-{縣市代碼}-{FNV-1a 雜湊}），同名同址重複者附加序號避免碰撞
④ 通過的寫入 shelters_nationwide.csv，沒通過的連同原因寫入 shelters_rejected.csv
```

重建：

```bash
cd server
dart run tool/build_nationwide_snapshot.dart --report              # 現行做法
dart run tool/build_nationwide_snapshot.dart --refresh --report    # 忽略快取，重抓上游
```

### 座標品質

單一全國 bounding box 沒有意義——會讓某縣市的錯誤座標被誤判成「落在臺灣境內所以正常」。逐縣市驗證後：**5,854 / 5,973 筆通過（98.0%）**，比臺北市時期單獨計算的 92.3% 還高。119 筆被拒的座標明顯分三類，記在 [`taiwan_bounds.dart`](server/lib/core/geo/taiwan_bounds.dart) 的註解裡：

| 縣市 | 通過率 | 備註 |
|---|---|---|
| 金門縣 | 80.0% | 8 筆金沙鎮座標落在海峽中，明顯偏移，未放寬 box 遷就 |
| 苗栗縣 | 92.4% | 多筆共用同一個「臺北 sentinel」座標（121.533/25.042），像是 geocode 失敗的預設值 |
| 桃園市 | 95.0% | 新屋區約 14 筆緯度打錯（26.9x 應為 24.9x） |
| 其餘 19 縣市 | 97–100% | |

API 每筆回應都帶 `座標來源`（`nfa_point_file`）與 `座標精度`（目前全國快照皆為 `exact`）。臺北市時期用 OpenData + 消防署 + 警政三方 join 產生的 `approx`／`name_match` 精度分級，只留在次要的 `server/data/shelter_coordinates.csv` 裡。

### 臺北市專屬管線（次要資料源）

`server/data/shelter_coordinates.csv` 由 [`server/tool/build_coordinates.dart`](server/tool/build_coordinates.dart) 產生，是專案最初（僅臺北市）的做法：臺北市 OpenData 本身沒有座標欄位，離線 join 消防署點位檔與北市警政 APP 座標補上。全國化後這條管線**不再是主資料源**，但保留下來——它是資料授權來源記錄，也是未來想幫臺北市補回「類型」「面積」等消防署沒有的欄位時的基礎。

```bash
cd server
dart run tool/build_coordinates.dart --report
```

還有一個 `--overpass` 旗標會拿 OpenStreetMap 補齊剩餘的點。**預設不要用**——它會讓產出的 CSV 落入具傳染性的 ODbL，見 [NOTICE.md](NOTICE.md)。

## API

Base URL 預設 `http://localhost:8080/api`。

另有 `GET /healthz`，供 Docker／負載平衡器檢查程序與座標表是否已就緒。

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
| `disasters` | — | 逗號分隔：`flood,earthquake,landslide,tsunami`，群內 OR |
| `spaces` | — | 逗號分隔：`indoor,outdoor`，群內 OR、與 `disasters` 群間 AND |
| `bbox` | — | `minLng,minLat,maxLng,maxLat`，單邊上限 2°，避免一次要整個台灣 |
| `limit` `offset` | — | 套用在**過濾後**的結果，`limit` 預設 `Env.maxSnapshotItems`（8000） |

```json
{
  "success": true,
  "dataSource": "nfa_point_file",
  "dataFreshness": "live",
  "dataUpdatedAt": "2026-08-22T19:09:51.934Z",
  "total": 5854,
  "truncated": false,
  "data": [{
    "收容所編號": "NFA-TPE-92adbc5938e85404",
    "名稱": "臺北市立螢橋國民中學",
    "門牌地址": "汀州路三段四號",
    "震災": "Y",
    "核子事故": "N",
    "服務里別": ["板溪里", "網溪里"],
    "座標x": 121.5265,
    "座標y": 25.019,
    "座標來源": "nfa_point_file",
    "座標精度": "exact"
  }]
}
```

`dataFreshness` 是 `live`（近期成功抓過上游）、`cached`（上游目前失敗，服務仍在快取有效期內的舊資料）或 `snapshot`（連快取都沒有，退回進版控的全國快照）三者之一——見下方 `/healthz`。`truncated` 是 `offset+limit` 是否小於過濾後的總筆數；`收容所編號` 現在是確定性產生的 ID（`NFA-{縣市代碼}-{雜湊}`），不是原始的 `序號`（消防署每次重新發布資料時 `序號` 會變動，不能拿來當穩定 ID）。

### `GET /shelters/nearby?lat=&lng=&radius=&limit=`

依距離排序，距離計算在 server 端完成。額外回傳 `距離公尺`，以及 `excludedWithoutCoordinates`（因為沒有座標而排除的筆數，讓 client 知道清單不完整）。

```bash
curl 'localhost:8080/api/shelters/nearby?lat=25.0478&lng=121.5170&radius=800&limit=3'
```

### `GET /shelters/clusters?bbox=&zoom=&disasters=&spaces=`

地圖視窗用的網格分群標記：回應是「質心 + 數量」而非逐筆資料，全台視野只回傳幾百個圓圈，而不是 5,854 筆紀錄（gzip 後從 ~470 KB 降到數 KB 級）。與其他端點不同，`bbox` 上限放寬到單邊 6°，**省略 `bbox` 代表全國**——回應本來就小，沒有理由逼 client 把全國切成 2° 的 tile。單點分群會內嵌完整 shelter 物件，client 不必再發第二個請求就能開啟詳情。

| 參數 | 說明 |
|---|---|
| `bbox` | 可省略（= 全國）；單邊上限 6° |
| `zoom` | **必填**，6–19，決定網格大小（Web Mercator 每像素度數，`cellPixels` 80） |
| `disasters` | 逗號分隔：`flood,earthquake,landslide,tsunami`，群內 OR |
| `spaces` | 逗號分隔：`indoor,outdoor`，群內 OR、與 `disasters` 群間 AND |
| `q` `city` `township` `type` 等 | 同 `/shelters`，全部在分群前套用 |

```json
{ "success": true, "dataFreshness": "live", "zoom": 13.0,
  "clusters": [
    { "count": 1, "lat": 25.0004, "lng": 121.4798, "shelter": { "名稱": "…", "座標x": 121.4798, "座標y": 25.0004, "…" } },
    { "count": 12, "lat": 25.0109, "lng": 121.5173 }
  ] }
```

### `GET /shelters/stats`

同一組過濾參數，回傳 `total`／`byType`／`byRegion`／`filters`，以及 `coordinateCoverage`：

```json
{ "total": 5854, "withCoordinates": 5854, "missing": 0, "ratio": 1.0,
  "bySource": { "nfa_point_file": 5854 } }
```

`coordinateCoverage` 是整個資料集的彙總。`byRegion` 的每一層（縣市／鄉鎮／村里）
另外各自帶一份同形狀的 `coordinateQuality`，讓資料品質頁面可以標出座標缺漏
集中在哪個行政區，而不只是知道全域缺了幾筆：

```json
{ "total": 3, "withCoordinates": 2, "missing": 1,
  "bySource": { "nfa_point_file": 2 }, "byConfidence": { "exact": 2 } }
```

`items` 與每層的 `shelters` 陣列**預設不回傳**——5,854 筆全國資料下，無過濾的
`/shelters/stats` 若每層都內嵌完整明細會變成好幾 MB 的 JSON，且同一筆資料會
重複出現 2-3 次。用 `?include=items,shelters` 才加回來。

### `GET /regions[?city=]`

不帶 `city` 回傳 22 縣市清單（各自的筆數與座標品質）；帶 `city` 回傳該縣市的鄉鎮清單。刻意不含 `shelters`／`items`，設計成每次開 App 都能便宜地打一次，供縣市選擇器與低 zoom 時的概覽使用。

```bash
curl 'localhost:8080/api/regions?city=高雄市'
```

## 設定

### server

`Env`（[`lib/core/config/env.dart`](server/lib/core/config/env.dart)）解析順序：**CLI 位置參數（僅 port） > 環境變數 > `.env` 檔 > 內建預設**。範本見 [`server/.env.example`](server/.env.example)。

| Key | 預設 | 說明 |
|---|---|---|
| `PORT` | `8080` | 也可用位置參數 `dart run bin/server.dart 3000` |
| `SNAPSHOT_CSV` | `data/shelters_nationwide.csv` | 全國快照路徑，upstream 失敗或看起來不合理時的備援 |
| `CACHE_TTL_SECONDS` | `600` | 上游資料快取時間 |
| `LOG_LEVEL` | `info` | `debug` \| `info` \| `warn` \| `error` |
| `NFA_POINT_FILE_URL` | 官方網址 | 覆寫消防署點位檔下載位置，僅在部署環境連不到預設主機時需要 |

不要直接讀 `Platform.environment`，一律走 `Env` 的 getter，否則優先序會不一致。

### flutter_codefest

**沒有任何金鑰要設定。** 唯一的建置期設定是後端位置：

```bash
flutter run   -d chrome --dart-define=API_BASE_URL=http://localhost:8080/api
flutter build web       --dart-define=API_BASE_URL=https://api.example.tw/api
```

Docker production build 使用 `API_BASE_URL=/api`，由同源反向代理連到後端；因此
同一個站點不會遇到 CORS 或 HTTPS mixed-content 問題。

- Android 模擬器連本機要用 `10.0.2.2`，不是 `localhost`。
- Flutter Web 若以 https 提供服務，後端也必須是 https，否則會被瀏覽器的 mixed-content 擋掉。

## 開發

```bash
# 後端
cd server
dart analyze        # 0 issues
dart test           # 175 passed

# 前端
cd flutter_codefest
flutter analyze     # 0 issues
flutter test        # 66 passed
```

### 端對端測試

`e2e/` 是獨立的 Playwright + TypeScript 專案，對著 `docker compose up --build`
起來的完整站台（Nginx + API + Flutter Web）跑幾個煙霧測試：首頁載入、搜尋、
開啟避難所詳情。不是對 mock 資料跑，而是實際打站台。

```bash
docker compose up -d --build
cd e2e
npm ci
npx playwright install --with-deps chromium
npx playwright test
docker compose down
```

Flutter Web 在啟用無障礙樹之前沒有可查詢的 DOM，測試會先點擊 Flutter 注入的
「Enable accessibility」按鈕（見 `e2e/tests/smoke.spec.ts` 的
`enableSemantics`），之後才能用文字定位元素。

CI（[`.github/workflows/ci.yml`](.github/workflows/ci.yml)）在每個 PR 跑 analyze、format、test、web build、e2e，以及 gitleaks 機密掃描。另有每週排程的 [upstream-data-check](.github/workflows/upstream-data-check.yml) 監看上游資料 schema 與覆蓋率變化。

貢獻前請讀 [CONTRIBUTING.md](CONTRIBUTING.md)，特別是**禁止提交清單**與安裝 pre-commit hook：

```bash
git config core.hooksPath .githooks
```

### 本機工具鏈現況

- Flutter 3.44 / Dart 3.12（pubspec 要求 sdk `^3.9.2`）
- 實務上可直接執行的目標是 `-d chrome` 與 macOS desktop
- iOS 需要 CocoaPods、Android 需要 Android SDK；本專案的 iOS/Android 設定（定位權限描述、entitlements、applicationId）已補齊但**未在本機實際建置驗證**


## 上游資料的已知特性

以下皆為 2026-08-09 對臺北市 OpenData 全部 401 筆的實測結果——**這是臺北市專屬管線（次要資料源）的特性，不是全國快照的**。這些規則的實作集中在 [`shelter_fields.dart`](server/lib/domain/entities/shelter_fields.dart)，**不要在別處重新實作**。全國快照（消防署點位檔）的災害欄位是單一欄位「適用災害類別」（逗號分隔的清單），室內／室外／無障礙欄位是「是」／「否」，解析邏輯在 [`nfa_shelter_mapper.dart`](server/lib/data/mappers/nfa_shelter_mapper.dart)。

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


## 最初版貢獻團隊

臺北程式設計節城市通微服務大黑客松 2025 · 團隊 30 · 喵主餓餓女裝

- **@twcat0503**（台貓）
- **@nangong5421**（南宮柳信）
- **@itousouta15**（伊藤蒼太）
- **@yuzen9622**（Z）
- **@NiaN0412**（q_nnn412）

並後續由

- **@itousouta15**（伊藤蒼太）
- **@twcat0503**（台貓）

持續開發貢獻


## 資料來源

- [臺北市可供避難收容處所一覽表](https://data.taipei/dataset/detail?id=aaf97773-3631-40e2-b3cc-da87bf2ce1d5) — 臺北市政府社會局
- [避難收容處所點位檔](https://data.gov.tw/dataset/73242) — 內政部消防署
- [北市警政APP_防空避難設備位置](https://data.taipei/dataset/detail?id=83eecdf1-3bbb-40f9-9484-b55b700c37ef) — 臺北市政府警察局
- [國土測繪圖資服務雲 WMTS](https://maps.nlsc.gov.tw/) — 內政部國土測繪中心
- [OpenStreetMap](https://www.openstreetmap.org/) — © OpenStreetMap contributors (ODbL)，**僅 `--overpass` opt-in 時使用，進版控的座標表不含其資料**

## 授權

程式碼以 **MIT** 授權（見 [LICENSE](LICENSE)）。

**資料檔另有授權**——`server/data/shelter_coordinates.csv` 全部來自政府資料開放授權條款第 1 版的兩個資料集，不含任何 share-alike 授權的資料。再散布前請讀 [NOTICE.md](NOTICE.md) 的標示要求。

地圖底圖由**內政部國土測繪中心**提供，依其使用規範，顯示圖磚的畫面必須標示來源。App 已在地圖左下角標示，**請勿移除**。

> **本系統為查詢輔助工具，非官方災害應變系統。**
> 上游資料非即時，且部分座標為推估值。**災時請以臺北市政府即時公告為準。**

安全性問題請見 [SECURITY.md](SECURITY.md)，不要開公開 issue。